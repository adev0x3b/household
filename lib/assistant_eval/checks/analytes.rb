# frozen_string_literal: true

module AssistantEval
  module Checks
    class Analytes < Base
      def self.key = "analytes"
      def self.argument = "How many analytes the profile has — a report in other words adds none"
      def self.example = 5

      def call(count)
        names = records.profile.analytes.order(:name).pluck(:name)
        "analytes: expected #{count}, got #{names.size} (#{names.join(", ")})" unless names.size == count
      end
    end
  end
end
