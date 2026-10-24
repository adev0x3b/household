# frozen_string_literal: true

module Assistant
  module Resources
    class Recipes < Resource
      def key = "recipe"
      def model = Recipe
      def search_columns = %i[name description]
      def writable = %w[name description]

      def scope(profile) = Recipe.where(id: Recipe.accessible_by(profile).select(:id))

      # What the viewer's pantry is short of is read for all the page's
      # recipes at once, so the model can prefer the ones it can cook.
      def summaries(recipes, profile)
        short = pantry_shortages(recipes.select(&:persisted?), profile)
        recipes.map do |recipe|
          { name: recipe.name, description: recipe.description.presence&.truncate(120),
            steps: recipe.recipe_steps.sort_by(&:position).map(&:instruction),
            ingredients: recipe.recipe_ingredients.map { |line| pantry_line(line) },
            short_in_pantry: short.fetch(recipe.id, []).presence }
        end
      end

      private

      def read_for_summaries(recipes)
        super
        load(recipes, :recipe_steps, recipe_ingredients: %i[ingredient unit])
      end
    end
  end
end
