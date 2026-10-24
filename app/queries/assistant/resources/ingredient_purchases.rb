# frozen_string_literal: true

module Assistant
  module Resources
    class IngredientPurchases < Resource
      def key = "ingredient_purchase"
      def model = IngredientPurchase
      def search_columns = %w[ingredients.name]
      def writable = %w[quantity purchased_on]
      def date_column = :purchased_on

      def scope(profile) = IngredientPurchase.where(id: IngredientPurchase.accessible_by(profile).select(:id)).joins(:ingredient)

      def summaries(purchases, _profile)
        purchases.map do |purchase|
          cost = purchase.cost
          { ingredient: purchase.ingredient.name, ingredient_id: purchase.ingredient_id, date: purchase.purchased_on.iso8601,
            quantity: [ purchase.quantity.to_s, purchase.unit&.name ].compact.join(" "), cost: money(cost), cost_id: cost&.id }
        end
      end

      private

      def read_for_summaries(purchases)
        super
        load(purchases, :ingredient, :unit)
      end
    end
  end
end
