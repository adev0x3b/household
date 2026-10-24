# frozen_string_literal: true

# Holds an import to the language's confirmed eval cases, with no model
# involved — so a failure here is always the dictionary's (the cases
# themselves are drafted by Lexicon::EvalCases before the import gets here).
# For each case, among its supply and two others (other confirmed cases):
#
#   the word in the language (singular, plural) → must pick the English-named supply
#   the English word (singular, plural)        → must pick the supply named in the language
#
# A wrong pick fails it outright (stock drawn from the wrong supply); at
# least FOUND_AT_LEAST of the picks must be right (a miss — nothing, or a
# tie — is a gap: the assistant would ask). Fewer than MIN_CASES confirmed
# cases means a person has to review them first (NeedsReview: the import
# waits, it doesn't fail). The pivot (English) is held to every translated
# language's confirmed cases.
#
#   Lexicon::DictionaryCheck.new(import, language).run  # => Summary, or nil (nothing to check the pivot with)
module Lexicon
  class DictionaryCheck
    class NeedsReview < StandardError; end

    FOUND_AT_LEAST = 0.8
    MIN_CASES = 3

    Summary = Data.define(:results, :waiting) do
      def total = results.size
      def found = results.count { _1["verdict"] == "found" }
      def wrong = results.count { _1["verdict"] == "wrong" }
      def missed = results.count { _1["verdict"] == "missed" }
      def rate = total.zero? ? 0.0 : found.fdiv(total)
      def pass? = total.positive? && wrong.zero? && rate >= FOUND_AT_LEAST

      def detail = "#{found}/#{total} picked right, #{wrong} wrong, #{missed} not found"

      def problem
        reasons = []
        reasons << "#{wrong} wrong pick(s)" if wrong.positive?
        reasons << "#{(rate * 100).round}% picked right, under #{(FOUND_AT_LEAST * 100).round}%" if rate < FOUND_AT_LEAST
        shown = results.reject { _1["verdict"] == "found" }.sort_by { _1["verdict"] == "wrong" ? 0 : 1 }.first(5)
        "#{reasons.join("; ")}. " + shown.map { |r| "#{r["concept"]}: “#{r["said"]}” → #{r["got"] || "nothing"} (expected #{r["expected"]})" }.join(" · ")
      end

      def to_h = { "results" => results, "waiting" => waiting, "detail" => detail, "status" => pass? ? "passed" : "failed" }
    end

    def initialize(import, language)
      @import = import
      @language = language
    end

    # The imports read: this one in place of its language's active one.
    def imports = LexiconImport.active_ids.merge(@language.code => @import.id)

    def run
      targets = target_languages
      return if targets.empty?

      matcher = Matcher.new(imports: imports)
      results = []
      waiting = []
      targets.each do |record|
        cases = record.lexicon_eval_cases.order(:id).to_a
        review = CaseReview.new(cases, record, imports)
        counted, held = review.counted, review.waiting
        waiting.concat(held.map { |kase, reason| { "language" => record.code, "concept" => kase.concept, "word" => kase.native_plural, "reason" => reason.to_s } })
        if counted.size < MIN_CASES
          next if @language.pivot? # that language isn't ready to judge English with

          raise NeedsReview, "#{counted.size} of #{cases.size} test cases are confirmed — confirm at least #{MIN_CASES} on the " \
                             "page (fix any the model got wrong), then Continue"
        end
        counted.each_with_index { |kase, i| results.concat(checks(matcher, record, kase, (counted.rotate(i + 1) - [ kase ]).first(2))) }
      end
      return if results.empty? && @language.pivot?

      Summary.new(results: results, waiting: waiting)
    end

    private

    def target_languages
      return [ LexiconLanguage.find_by!(code: @language.code) ] unless @language.pivot?

      LexiconLanguage.where(code: LexiconImport.active_ids.keys, role: "translated").order(:code).to_a
    end

    def checks(matcher, record, kase, others)
      english = ->(c) { capitalize(EvalCases.english_plural(c)) }
      native = ->(c) { capitalize(c.native_plural) }
      english_names = [ kase, *others ].map(&english)
      native_names = [ kase, *others ].map(&native)
      [ kase.native_plural, kase.native_singular ].uniq.map { |said| check(matcher, record, kase, said, english_names, english.call(kase), "to_english") } +
        [ EvalCases.english_plural(kase), kase.concept ].uniq.map { |said| check(matcher, record, kase, said, native_names, native.call(kase), "from_english") }
    end

    def check(matcher, record, kase, said, names, expected, direction)
      pick = matcher.pick(names, said)
      verdict = if pick.name == expected then "found" elsif pick.name then "wrong" else "missed" end
      { "language" => record.code, "concept" => kase.concept, "direction" => direction, "said" => said, "supplies" => names,
        "expected" => expected, "got" => pick.name || (pick.candidates.any? ? "a tie: #{pick.candidates.join(", ")}" : nil), "verdict" => verdict }
    end

    def capitalize(name) = name.to_s.sub(/\A\p{Ll}/) { _1.upcase }
  end
end
