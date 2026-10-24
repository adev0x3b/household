# frozen_string_literal: true

# Which catalog row a spoken name means: a Supply, an Analyte, a Unit. An
# exact name wins, ignoring case and accents ("unita" is "Unità"). Else the
# one row whose name's words are all in what was said ("needles" in "needles
# 25G"), or the other way round ("vitamin d" in "Vitamin D (25-OH)"). Else
# the one row the name is a typo of ("Estradio1", "Eritroci"), by
# TextMatch.typo?, which never turns "HDL" into "LDL". Nothing found, or
# several, is nil, and the caller creates a row named as said.
#
# `strict: true` (a purchase that adds to stock) skips the word-subset step:
# "milk" must not become "Oat milk" and put the shopping into the wrong jar.
module Assistant
  class NameMatch
    # The rows read past an exact match, by shared words or by spelling: a
    # household's catalog is small, so the one meant is among the first.
    CANDIDATES = 20

    def self.find(scope, spoken, strict: false) = new(scope, spoken, strict: strict).record

    def initialize(scope, spoken, strict: false)
      @scope = scope
      @strict = strict
      @name = spoken.to_s.squish
    end

    def record
      return @record if defined?(@record)
      return @record = nil if @name.blank?

      @record = exact || (@strict ? nil : single_candidate) || single_typo
    end

    # Only the exact step: the name, ignoring case and accents.
    def exact = @scope.where("unaccent(lower(#{column})) = unaccent(lower(?))", @name).first

    private

    def column = "#{@scope.klass.quoted_table_name}.name"

    def single_candidate
      said = words(@name)
      return if said.empty?

      long = said.select { |word| word.length >= 3 }.presence || said
      candidates = @scope.where(TextMatch.contains([ column ], long.to_a)).limit(CANDIDATES)
        .select { |row| (known = words(row.name)).any? && (known.subset?(said) || said.subset?(known)) }
      candidates.one? ? candidates.first : nil
    end

    # The closest rows by trigram similarity, kept only if the name is a
    # typo of theirs; one survivor wins.
    def single_typo
      return if TextMatch.fuzzy_words([ @name ]).empty?

      nearest = @scope.where("#{TextMatch.similarity(column, @name)} >= 0.3")
        .reorder(Arel.sql("#{TextMatch.similarity(column, @name)} DESC")).limit(CANDIDATES)
      typos = nearest.select { |row| TextMatch.typo?(@name, row.name) }
      typos.one? ? typos.first : nil
    end

    # Every word counts, short ones too: "Vitamin Q" is not "Vitamin D".
    def words(text) = TextMatch.fold(text).scan(/[[:alnum:]]+/).to_set
  end
end
