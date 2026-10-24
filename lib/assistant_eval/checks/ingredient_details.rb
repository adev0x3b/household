# frozen_string_literal: true

module AssistantEval
  module Checks
    # The quantity is what's on hand; the cost is its latest purchase's.
    class IngredientDetails < Base
      def self.key = "ingredient_details"
      def self.argument = "Ingredient name substring → quantity on hand / unit / cost (of its latest purchase)"
      def self.example = { "pasta" => { "quantity" => 500, "unit" => "g", "cost" => 0.99 } }

      def call(expected)
        wrong = expected.filter_map do |key, want|
          ingredient = records.ingredients.to_a.find { |i| i.name.downcase.include?(key.to_s.downcase) }
          next "#{key}: no ingredient" if ingredient.nil?

          problems = problems_of(ingredient, want)
          "#{key}: #{problems.join(", ")}" if problems.any?
        end
        "ingredient_details: #{wrong.join("; ")}" if wrong.any?
      end

      private

      def problems_of(ingredient, want)
        problems = []
        problems << "quantity #{ingredient.quantity}" if want["quantity"] && !same_number?(ingredient.quantity, want["quantity"])
        problems << "unit #{ingredient.unit&.name}" if want["unit"] && !ingredient.unit&.name.to_s.casecmp?(want["unit"].to_s)
        if want["cost"]
          cost = ingredient.ingredient_purchases.order(:purchased_on, :id).last&.costs&.first
          problems << "cost #{amount(cost).to_f}" unless same_number?(amount(cost), want["cost"])
        end
        problems
      end
    end
  end
end
