# frozen_string_literal: true

module AssistantEval
  module Checks
    class Meals < Base
      def self.key = "meals"
      def self.argument = "How many meals exist"
      def self.example = 3

      def call(count)
        have = records.days("meal").count
        "meals: expected #{count}, got #{have}" unless have == count
      end
    end
  end
end
