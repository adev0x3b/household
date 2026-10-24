# frozen_string_literal: true

module Assistant
  module Resources
    class Ingredients < Resource
      def key = "ingredient"
      def model = Ingredient
      def search_columns = %i[name]
      def writable = %w[name quantity unit_name category]
      def enums = { "category" => Ingredient.categories.keys }

      def scope(profile) = profile.ingredients

      def summaries(ingredients, _profile)
        ingredients.map do |ingredient|
          { name: ingredient.name, quantity: ingredient.quantity.to_s, unit: ingredient.unit&.name, category: ingredient.category }
        end
      end

      private

      def read_for_summaries(ingredients)
        super
        load(ingredients, :unit)
      end
    end
  end
end
