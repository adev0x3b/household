# frozen_string_literal: true

# Which of a few saved names (a household's supplies) the user's words
# mean, when the two are written in different languages or word forms:
#
#   Lexicon::Matcher.find(Supply.where(…), "needle")   # => #<Supply name: "Aghi">
#   Lexicon::Matcher.new.pick(%w[Aghi Siringhe], "ago") # => #<Pick name="Aghi" candidates=[]>
#
# Two names mean the same thing when they share a lemma in a language the
# lexicons know, or when a meaning of one (an Italian noun's English
# glosses) is an English key of the other. The closest link wins, and a
# tie is no match: guessing between two supplies would move the wrong
# stock, so the caller asks with the tied names as candidates. A language
# with no active import is not read, and only what is spelled alike
# matches in it.
module Lexicon
  class Matcher
    Pick = Data.define(:name, :candidates)
    Reading = Data.define(:lemmas, :english)

    # A link's rank: lower is closer. A name's whole text or head word links
    # at its sense's rank; the weights below are added for a link that is
    # less sure, so a plain sense of the head word always beats a synonym,
    # a narrowed sense, a guessed compound or a word that isn't the noun.
    SAME = -1
    WEAK_WORD = 20
    SYNONYM = 5
    QUALIFIED = 10
    COMPOUND = 2
    MIN_HEAD = 4
    MIN_FIRST = 3
    LINKING = %w[es s en n er e].freeze
    MAX_NAMES = 500

    def self.find(scope, said)
      rows = scope.limit(MAX_NAMES).pluck(:id, :name)
      pick = new.pick(rows.map(&:last), said)
      pick.name && scope.find_by(id: rows.find { |_, name| name == pick.name }&.first)
    end

    # The imports matching reads: the active ones, unless LEXICON_IMPORTS
    # ("it=12,en=4") puts a candidate in. Lexicon::AgentEval sets it, so an
    # import is tested against the agent before anyone matches with it.
    def self.default_imports
      override = ENV["LEXICON_IMPORTS"].to_s.split(",").filter_map { |pair| pair.split("=", 2).map(&:strip) if pair.include?("=") }.to_h
      LexiconImport.active_ids.merge(override.transform_values(&:to_i))
    end

    # imports: { language code => import id } to read (default: default_imports);
    # languages: their settings by code (default: Lexicon::Config.languages).
    def initialize(imports: self.class.default_imports, languages: Config.languages)
      @imports = imports.transform_keys(&:to_s)
      @languages = @imports.keys.filter_map { |code| languages[code] }
      @pivot = @languages.find(&:pivot?)
      @forms = {}
      @meanings = {}
      @pivot_keys = {}
      @readings = {}
    end

    def pick(names, said)
      names = names.compact.uniq
      return Pick.new(name: nil, candidates: []) if Text.fold(said).empty? || names.empty?

      prefetch([ said, *names ])
      linked = names.filter_map { |name| (rank = link(said, name)) && [ name, rank ] }.sort_by(&:last)
      return Pick.new(name: nil, candidates: []) if linked.empty?

      tied = linked.take_while { _2 == linked.first.last }
      tied.size > 1 ? Pick.new(name: nil, candidates: tied.map(&:first)) : Pick.new(name: tied.first.first, candidates: [])
    end

    # The rank of the closest way said and name mean the same thing; nil if none.
    def link(said, name)
      return SAME if (Text.english_keys(said) & Text.english_keys(name)).any?

      a = reading(said)
      b = reading(name)
      shared = shared_lemmas(a, b)
      return SAME if shared.include?(0)

      [ shared, ranks_between(a, b), ranks_between(b, a), english_overlap(a, b) ].flatten.compact.min
    end

    # A name read every way the lexicons allow: the lemmas of its head word
    # in each translated language, weighted 0 for the name or its head word,
    # COMPOUND for a compound's head and WEAK_WORD for the noun before it;
    # and its English keys.
    def reading(name)
      @readings[name] ||= begin
        words = Text.words(name)
        lemmas = {}
        add = ->(ids, weight) { ids.each { lemmas[_1] = [ lemmas[_1], weight ].compact.min } }
        @languages.reject(&:pivot?).each do |language|
          head = language.head_first? ? words.first : words.last
          found = [ words.join(" "), head ].uniq.flat_map { lemma_ids(language.code, _1) }
          add.call(found, 0)
          next if found.any? || language.head_first? || head.nil?

          compound_head, first = compound(language.code, head)
          add.call(compound_head, COMPOUND)
          add.call(first, WEAK_WORD)
        end
        Reading.new(lemmas: lemmas, english: english_keys(words))
      end
    end

    # Reads ahead what reading many names needs (every word's forms, one
    # query per import, then their lemmas' meanings and keys), so a pick over
    # a few dozen names doesn't query word by word.
    def prefetch(names)
      keys = names.flat_map do |name|
        words = Text.words(name)
        [ words.join(" "), words.first, words.last, *words.flat_map { Text.english_keys(_1) }, *Text.english_keys(words.join(" ")) ].compact
      end.uniq
      @imports.each_key { lookup(_1, keys) }
      read_lemmas(@forms.values.flatten.uniq)
      self
    end

    # Whether a language's dictionary lists the word.
    def listed?(code, key) = lemma_ids(code, key).any?

    private

    # A noun both names read as, a compound's head included. The noun before
    # a compound's head never counts: "Wattebausch" and "Wattestäbchen"
    # share a word, not a noun.
    def shared_lemmas(a, b)
      (a.lemmas.keys & b.lemmas.keys).filter_map do |lemma_id|
        a.lemmas[lemma_id] + b.lemmas[lemma_id] if a.lemmas[lemma_id] < WEAK_WORD && b.lemmas[lemma_id] < WEAK_WORD
      end
    end

    # In a language whose names end in their noun (German), a word the
    # dictionary doesn't list is read as a compound. Its head is the longest
    # noun it ends with ("Einmalhandschuhe" ends with "Handschuhe"), and the
    # first noun is what comes before it, linking letters aside. Returns the
    # lemma ids of both, both empty when the word ends with no noun.
    def compound(code, word)
      cuts = (MIN_FIRST..(word.length - MIN_HEAD))
      lookup(code, cuts.map { word[_1..] })
      cut = cuts.find { lemma_ids(code, word[_1..]).any? }
      return [ [], [] ] if cut.nil?

      first = word[0...cut]
      firsts = [ first, *LINKING.filter_map { first.delete_suffix(_1) if first.end_with?(_1) && first.length - _1.length >= MIN_FIRST } ]
      lookup(code, firsts)
      [ lemma_ids(code, word[cut..]), firsts.lazy.map { lemma_ids(code, _1) }.find(&:any?) || [] ]
    end

    # Meanings of one side's translated lemmas that are English keys of the other.
    def ranks_between(from, to)
      from.lemmas.flat_map do |lemma_id, weight|
        meanings(lemma_id).filter_map do |key, rank, qualified, kind|
          next unless kind == "gloss" && to.english.key?(key)
          # A narrowed sense counts only as the word's first: "gauze (fabric)"
          # is garza, but "needle (of a barometer)", lancetta's second sense,
          # must never put lancets on someone's needles.
          next if qualified && rank.positive?

          rank + (qualified ? QUALIFIED : 0) + to.english[key] + weight
        end
      end
    end

    # Two English names with the same noun ("gloves" and "Latex gloves",
    # "vial" and "Phials" through its synonym). Only the main keys count:
    # "cotton balls" and "cotton swabs" share a word, not a noun.
    def english_overlap(a, b)
      a.english.filter_map { |key, weight| weight + b.english[key] if weight < WEAK_WORD && b.english[key].to_i < WEAK_WORD && b.english.key?(key) }
    end

    # The English keys a name reads as, by weight: the whole name and its
    # head word, the other words weaker, and each as its English lemma
    # ("gloves" as glove) and that lemma's synonyms ("vial" as phial).
    def english_keys(words)
      return {} if words.empty?

      keys = {}
      add = ->(text, weight) { Text.english_keys(text).each { |key| keys[key] = [ keys[key], weight ].compact.min } }
      add.call(words.join(" "), 0)
      add.call(words.last, 0)
      words.each { add.call(_1, WEAK_WORD) }
      return keys unless @pivot

      keys.dup.each do |key, weight|
        lemma_ids(@pivot.code, key).each do |lemma_id|
          meanings(lemma_id).each do |synonym, _, _, kind|
            keys[synonym] = [ keys[synonym], weight + SYNONYM ].compact.min if kind == "synonym"
          end
          pivot_lemma_keys(lemma_id).each { |lemma_key| keys[lemma_key] = [ keys[lemma_key], weight ].compact.min }
        end
      end
      keys
    end

    def lemma_ids(code, key)
      import_id = @imports[code]
      return [] if import_id.nil?

      @forms.fetch([ import_id, key ]) do
        @forms[[ import_id, key ]] = LexiconForm.where(lexicon_import_id: import_id, key: key).pluck(:lexicon_lemma_id)
      end
    end

    def pivot_lemma_keys(lemma_id) = @pivot_keys[lemma_id] ||= LexiconLemma.where(id: lemma_id).pluck(:key)

    def meanings(lemma_id)
      @meanings.fetch(lemma_id) do
        @meanings[lemma_id] = LexiconMeaning.where(lexicon_lemma_id: lemma_id).order(:rank).pluck(:key, :rank, :qualified, :kind)
      end
    end

    # The meanings and keys of the lemmas not read yet, in one query each.
    def read_lemmas(ids)
      missing = ids.reject { @meanings.key?(_1) }
      return if missing.empty?

      meanings = LexiconMeaning.where(lexicon_lemma_id: missing).order(:rank).pluck(:lexicon_lemma_id, :key, :rank, :qualified, :kind).group_by(&:first)
      keys = LexiconLemma.where(id: missing).pluck(:id, :key).group_by(&:first)
      missing.each do |id|
        @meanings[id] = Array(meanings[id]).map { _1.drop(1) }
        @pivot_keys[id] = Array(keys[id]).map(&:last)
      end
    end

    # Loads the lemma ids of the keys not read yet, in one query.
    def lookup(code, keys)
      import_id = @imports[code]
      return if import_id.nil?

      missing = keys.uniq.reject { @forms.key?([ import_id, _1 ]) }
      return if missing.empty?

      found = LexiconForm.where(lexicon_import_id: import_id, key: missing).pluck(:key, :lexicon_lemma_id).group_by(&:first)
      missing.each { |key| @forms[[ import_id, key ]] = Array(found[key]).map(&:last) }
    end
  end
end
