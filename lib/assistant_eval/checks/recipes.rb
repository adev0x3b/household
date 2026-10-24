# frozen_string_literal: true

module AssistantEval
  module Checks
    class Recipes < Base
      def self.key = "recipes"
      def self.argument = "How many recipes exist"
      def self.example = 1

      def call(count)
        have = records.recipes.count
        "recipes: expected #{count}, got #{have}" unless have == count
      end
    end
  end
end
