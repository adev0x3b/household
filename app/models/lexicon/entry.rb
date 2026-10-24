# frozen_string_literal: true

# One noun from a kaikki.org line, reduced to what matching needs:
#
#   Entry.from_kaikki(line_hash, pivot: false)
#   # => #<Entry word="ago" forms=["ago", "aghi"] meanings=[["needle", 0, false]] synonyms=[]>
#
# A translated language keeps its glosses, which English Wiktionary writes
# in English: each gloss split into its meanings, numbered by position
# (rank: the first sense is the usual one), a parenthetical marking a
# narrowed one ("needle (of a barometer)" → qualified), and glosses that
# point at other words ("alternative form of…", "synonym of…") left out. The
# pivot (English) keeps its synonyms instead — two-way ones only, decided by
# Lexicon::Import once every entry is read.
module Lexicon
  Entry = Data.define(:word, :forms, :meanings, :synonyms)

  class Entry
    # Glosses that point at another word instead of saying what this one means.
    # (Not a /x regex: that would drop the spaces in "name of", "short for".)
    POINTERS = Regexp.new("\\A(?:#{%w[alternative abbreviation acronym initialism synonym ellipsis diminutive augmentative feminine
                                      masculine obsolete clipping misspelling archaic dated nonstandard].join("|")}|" \
                          "name of|plural of|short for|form of)")
    MAX_MEANING_WORDS = 3

    def self.from_kaikki(data, pivot:)
      return unless data["pos"] == "noun"

      word = data["word"].to_s.squish
      return if word.empty?

      plurals = Array(data["forms"]).filter_map { |form| form["form"] if Array(form["tags"]).include?("plural") }
      forms = ([ word ] + plurals).map { Text.fold(_1) }.reject(&:empty?).uniq
      if pivot
        synonyms = (Array(data["synonyms"]) + Array(data["senses"]).flat_map { Array(_1["synonyms"]) })
          .filter_map { Text.fold(_1["word"]).presence }.uniq - [ Text.fold(word) ]
        new(word: word, forms: forms, meanings: [], synonyms: synonyms)
      else
        new(word: word, forms: forms, meanings: meanings_of(data), synonyms: [])
      end
    end

    # [[english_key, rank, qualified], …] from the glosses, in order.
    def self.meanings_of(data)
      glosses = Array(data["senses"]).flat_map { Array(_1["glosses"]) }.uniq
      glosses.each_with_index.flat_map do |gloss, rank|
        parts(gloss).flat_map do |part|
          qualified = part.match?(/\(.*?\)/)
          text = part.gsub(/\(.*?\)|“.*?”|".*?"/, "").squish.delete_suffix(".")
          next [] if text.empty? || text.downcase.match?(POINTERS) || text.split.size > MAX_MEANING_WORDS

          Text.english_keys(text).map { [ _1, rank, qualified ] }
        end
      end.uniq { _1.first(2) }
    end

    # A gloss cut at each , and ; outside a parenthetical or a quote: "gauze
    # (very thin fabric, generally used for medical purposes)" is one meaning,
    # not two halves too long to keep (Mull lost its only sense that way).
    def self.parts(gloss) = gloss.scan(/(?:\([^)]*\)?|“[^”]*”?|"[^"]*"?|[^,;(“"])+/)

    def key = Text.fold(word)

    # Whether keeping it adds anything over its own spelling: an English noun
    # with neither a plural nor a synonym doesn't.
    def useful? = meanings.any? || synonyms.any? || forms.size > 1
  end
end
