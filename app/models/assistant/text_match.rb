# frozen_string_literal: true

# SQL for matching what the user said against a text column, blind to
# accents ("unita" finds "Unità"). Every search starts with `contains`, a
# substring match. `similar` and `score` are the fallback for typos
# ("estradio1" finds "Estradiol"), through pg_trgm's word_similarity. Callers
# use it only when the exact match found nothing, so a search that finds one
# record today never starts finding several.
#
# `typo?` is stricter, for taking a name as one catalog row without asking:
# short words must be equal, so "HDL" never becomes "LDL" nor "T3" "T4".
module Assistant
  module TextMatch
    SIMILARITY = 0.5
    FUZZY_MIN_LENGTH = 4
    TYPO_MIN_LENGTH = 5

    # Words that name nothing, in the app's languages and folded as `fold`
    # makes them. A search matches any of its words, so without this list
    # every new task with a "the" in it would look like a duplicate.
    STOP_WORDS = %w[
      an and at by for from in into of on or the to with my your our
      il lo la gli le un uno una di da del dello della dei degli delle al allo alla ai agli alle
      dal dalla dai nel nella nei nelle sul sulla sui con per tra fra ed mio mia miei mie
    ].to_set.freeze

    module_function

    # The words of a search that name something; all of them when none does.
    def significant(words)
      kept = words.reject { |word| STOP_WORDS.include?(word) }
      kept.empty? ? words : kept
    end

    # Any column contains any word (columns are trusted SQL: "table.column").
    def contains(columns, words)
      columns.product(words).map do |column, word|
        sanitize([ "unaccent(#{column}::text) ILIKE unaccent(?)", "%#{ActiveRecord::Base.sanitize_sql_like(word)}%" ])
      end.join(" OR ")
    end

    # Any column is close to any word long enough to judge (nil if none is).
    def similar(columns, words)
      words = fuzzy_words(words)
      return if words.empty?

      columns.product(words).map { |column, word| sanitize([ "#{similarity(column, word)} >= ?", SIMILARITY ]) }.join(" OR ")
    end

    # The best similarity of any word to any column, for ORDER BY.
    def score(columns, words)
      "GREATEST(#{columns.product(fuzzy_words(words)).map { |column, word| similarity(column, word) }.join(", ")})"
    end

    def fuzzy_words(words) = words.select { |word| word.length >= FUZZY_MIN_LENGTH }

    def similarity(column, word)
      sanitize([ "word_similarity(unaccent(lower(?)), unaccent(lower(#{column}::text)))", word ])
    end

    # Is `said` the name `known` with a typo or an OCR slip?
    def typo?(said, known)
      said = words(said)
      known = words(known)
      return false if said.empty? || said.size != known.size

      said.zip(known).all? { |a, b| a == b || close?(a, b) }
    end

    def close?(a, b)
      return false if [ a.length, b.length ].min < TYPO_MIN_LENGTH

      DidYouMean::Levenshtein.distance(a, b) <= [ 1, [ a.length, b.length ].min / 4 ].max
    end

    def words(text) = fold(text).scan(/[[:alnum:]]+/)

    # Lower case without accents, as unaccent(lower(…)) does in SQL.
    def fold(text) = text.to_s.downcase.unicode_normalize(:nfd).gsub(/\p{Mn}/, "")

    def sanitize(sql) = ActiveRecord::Base.sanitize_sql(sql)
  end
end
