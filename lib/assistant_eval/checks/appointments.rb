# frozen_string_literal: true

module AssistantEval
  module Checks
    class Appointments < Base
      def self.key = "appointments"
      def self.argument = "How many appointments exist"
      def self.example = 1

      def call(count)
        have = records.appointments.count
        "appointments: expected #{count}, got #{have}" unless have == count
      end
    end
  end
end
