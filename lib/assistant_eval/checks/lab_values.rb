# frozen_string_literal: true

module AssistantEval
  module Checks
    class LabValues < Base
      def self.key = "lab_values"
      def self.argument = "Analyte → value on the latest lab report"
      def self.example = { "Cobalamin" => 250, "Calcium" => 3 }

      def call(expected)
        result = records.latest_lab
        return "lab_values: no lab result" if result.nil?

        have = result.lab_test_result_entries.includes(:analyte).to_h { |e| [ e.analyte.name.downcase, e.value.to_s ] }
        wrong = expected.reject { |name, value| same_number?(have[name.to_s.downcase], value) }
        "lab_values: expected #{expected}, got #{have}" if wrong.any?
      end
    end
  end
end
