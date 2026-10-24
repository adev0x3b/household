# frozen_string_literal: true

module Lexicon
  class AgentEval
    # The assistant tests as an import's report keeps them (Summary#to_h),
    # read back for the admin page. Empty before the step has run.
    Report = Data.define(:status, :detail, :results, :passed, :scored, :rerun) do
      def self.of(import)
        saved = import&.report&.fetch("agent", nil) || {}
        new(status: saved["status"].to_s, detail: saved["detail"], results: Array(saved["results"]).map { Result.of(_1) },
            passed: saved["passed"], scored: saved["scored"], rerun: saved["rerun"].present?)
      end

      def any? = status.present?
      def running? = status == "running"
      def passed? = status == "passed"
      def failing = results.reject(&:passed?)
    end

    # One scenario's run. Its name says what it tested:
    # "it_test_strip_dose_native_supplies" is Italian's "test strip", dose_native_supplies.
    Result = Data.define(:scenario, :status, :failures, :error, :tools) do
      def self.of(saved)
        new(scenario: saved["scenario"].to_s, status: saved["status"].to_s, failures: Array(saved["failures"]), error: saved["error"],
            tools: saved["tools"])
      end

      def passed? = status == "passed"
      def kind = AgentEval.kind_of(scenario)
      def code = scenario.delete_suffix("_#{kind}").split("_", 2).first
      def concept = scenario.delete_suffix("_#{kind}").split("_", 2).last.to_s.tr("_", " ")
      def control? = AgentEval.control?(scenario)

      # Why it didn't pass, in a line.
      def reason = failures.first || error
    end
  end
end
