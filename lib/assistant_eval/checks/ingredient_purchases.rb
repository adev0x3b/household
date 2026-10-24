# frozen_string_literal: true

module AssistantEval
  module Checks
    class IngredientPurchases < Base
      def self.key = "ingredient_purchases"
      def self.argument = "How many grocery purchases (food bought) exist"
      def self.example = 2

      def call(count)
        have = records.ingredient_purchases.count
        "ingredient_purchases: expected #{count}, got #{have}" unless have == count
      end
    end
  end
end
