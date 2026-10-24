# frozen_string_literal: true

module AssistantEval
  module Checks
    # The latest purchase of the ingredient is judged. Its quantity is in the
    # ingredient's own unit: 500 g bought onto an ingredient kept in kg is 0.5.
    class IngredientPurchaseDetails < Base
      def self.key = "ingredient_purchase_details"
      def self.argument = "Ingredient name substring → quantity bought / unit / cost / paid (payment method) / category / date"
      def self.example = { "flour" => { "quantity" => 500, "unit" => "g", "cost" => 1.2, "paid" => "card" } }

      def call(expected)
        wrong = expected.filter_map do |key, want|
          matching = records.ingredient_purchases.select { |p| p.ingredient.name.downcase.include?(key.to_s.downcase) }
          purchase = matching.max_by { |p| [ p.purchased_on, p.id ] }
          next "#{key}: no purchase" if purchase.nil?

          problems = problems_of(purchase, want)
          "#{key}: #{problems.join(", ")}" if problems.any?
        end
        "ingredient_purchase_details: #{wrong.join("; ")}" if wrong.any?
      end

      private

      def problems_of(purchase, want)
        cost = purchase.costs.first
        problems = []
        problems << "quantity #{purchase.quantity.to_f}" if want["quantity"] && !same_number?(purchase.quantity, want["quantity"])
        problems << "unit #{purchase.unit&.name}" if want["unit"] && !purchase.unit&.name.to_s.casecmp?(want["unit"].to_s)
        problems << "cost #{amount(cost).to_f}" if want["cost"] && !same_number?(amount(cost), want["cost"])
        problems << "paid #{paid_with(cost)}/#{cost&.status}" if want["paid"] && !(paid_with(cost) == want["paid"] && cost&.completed?)
        problems << "category #{category_of(cost)}" if want["category"] && category_of(cost) != want["category"].to_s
        problems << "date #{purchase.purchased_on}" if want["date"] && purchase.purchased_on != Date.parse(want["date"].to_s)
        problems
      end
    end
  end
end
