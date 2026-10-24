# frozen_string_literal: true

module AssistantEval
  module Checks
    class LabResults < Base
      def self.key = "lab_results"
      def self.argument = "How many lab reports exist"
      def self.example = 1

      def call(count)
        have = records.lab_results.count
        "lab_results: expected #{count}, got #{have}" unless have == count
      end
    end
  end
end
