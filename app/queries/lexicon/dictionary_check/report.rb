# frozen_string_literal: true

module Lexicon
  class DictionaryCheck
    # The dictionary check as an import's report keeps it (Summary#to_h),
    # read back for the admin page. Empty before the step has run.
    Report = Data.define(:status, :detail, :results) do
      def self.of(import)
        saved = import&.report&.fetch("dictionary", nil) || {}
        new(status: saved["status"].to_s, detail: saved["detail"], results: Array(saved["results"]).map { Pick.of(_1) })
      end

      def any? = status.present?
      def passed? = status == "passed"
    end

    # What the matcher picked for one word among a case's supplies: found
    # (right), wrong, or missed (nothing, or a tie).
    Pick = Data.define(:said, :supplies, :expected, :got, :verdict) do
      def self.of(saved)
        new(said: saved["said"].to_s, supplies: Array(saved["supplies"]), expected: saved["expected"], got: saved["got"], verdict: saved["verdict"].to_s)
      end
    end
  end
end
