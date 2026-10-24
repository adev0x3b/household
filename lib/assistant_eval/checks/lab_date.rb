# frozen_string_literal: true

module AssistantEval
  module Checks
    class LabDate < Base
      def self.key = "lab_date"
      def self.argument = "Date of the latest lab report"
      def self.example = "2026-09-16"

      def call(date)
        have = records.latest_lab&.date
        "lab_date: expected #{date}, got #{have}" unless have == Date.parse(date.to_s)
      end
    end
  end
end
