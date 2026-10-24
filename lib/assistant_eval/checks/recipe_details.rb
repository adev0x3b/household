# frozen_string_literal: true

module AssistantEval
  module Checks
    class RecipeDetails < Base
      def self.key = "recipe_details"
      def self.argument = "Recipe name substring → ingredients_count / steps_count"
      def self.example = { "carbonara" => { "ingredients_count" => 3 } }

      def call(expected)
        wrong = expected.filter_map do |key, want|
          recipe = records.recipes.to_a.find { |r| r.name.downcase.include?(key.to_s.downcase) }
          next "#{key}: no recipe" if recipe.nil?

          problems = []
          problems << "ingredients_count #{recipe.recipe_ingredients.count}" if want["ingredients_count"] && recipe.recipe_ingredients.count != want["ingredients_count"].to_i
          problems << "steps_count #{recipe.recipe_steps.count}" if want["steps_count"] && recipe.recipe_steps.count != want["steps_count"].to_i
          "#{key}: #{problems.join(", ")}" if problems.any?
        end
        "recipe_details: #{wrong.join("; ")}" if wrong.any?
      end
    end
  end
end
