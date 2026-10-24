# frozen_string_literal: true

module AssistantEval
  module Checks
    class LabStatus < Base
      def self.key = "lab_status"
      def self.argument = "Status of the latest lab report"
      def self.example = "completed"

      def call(status)
        have = records.latest_lab&.status
        "lab_status: expected #{status}, got #{have}" unless have == status.to_s
      end
    end
  end
end
