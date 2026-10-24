# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # A recipe with its steps and ingredients. One without any step is just
    # a name, so its steps are asked for once.
    class Recipes < NamedRecords
      # Its ordered steps: each { instruction }, or the words alone.
      def steps
        @steps ||= Array(draft.payload["steps"]).filter_map do |step|
          instruction = (step.is_a?(Hash) ? step.to_h["instruction"] : step).to_s.strip
          RecipeStep.new(instruction: instruction) unless instruction.empty?
        end
      end

      def missing_parts = steps.empty? ? super + [ { "field" => "recipe.steps" } ] : super

      def notes = new_ingredient_names.any? ? [ "new ingredients: #{new_ingredient_names.join(", ")}" ] : []

      private

      def build
        recipe = Recipe.new(writable_attributes.merge("profile" => profile))
        steps.each { |step| recipe.recipe_steps << step }
        pantry_lines("ingredients", RecipeIngredient).each { |line| recipe.recipe_ingredients << line }
        recipe
      end
    end
  end
end
