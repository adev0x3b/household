# frozen_string_literal: true

module AssistantEval
  module Checks
    class Ingredients < Base
      def self.key = "ingredients"
      def self.argument = "How many ingredients are in the pantry"
      def self.example = 3

      def call(count)
        have = records.ingredients.count
        "ingredients: expected #{count}, got #{have}" unless have == count
      end
    end
  end
end
