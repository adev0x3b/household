# frozen_string_literal: true

module AssistantEval
  module Checks
    class PurchaseDetails < Base
      def self.key = "purchase_details"
      def self.argument = "Part of a supply name → quantity / cost / paid (payment method) / therapy"
      def self.example = { "needles" => { "quantity" => 100, "cost" => 12, "paid" => "card" } }

      def call(expected)
        wrong = expected.filter_map do |key, want|
          purchase = records.supply_purchases.find { |p| p.supply.name.downcase.include?(key.to_s.downcase) }
          next "#{key}: no purchase" if purchase.nil?

          problems = problems_of(purchase, want)
          "#{key}: #{problems.join(", ")}" if problems.any?
        end
        "purchase_details: #{wrong.join("; ")}" if wrong.any?
      end

      private

      def problems_of(purchase, want)
        cost = purchase.costs.first
        problems = []
        problems << "quantity #{purchase.quantity_purchased.to_f}" if want["quantity"] && !same_number?(purchase.quantity_purchased, want["quantity"])
        problems << "cost #{amount(cost).to_f}" if want["cost"] && !same_number?(amount(cost), want["cost"])
        problems << "paid #{paid_with(cost)}/#{cost&.status}" if want["paid"] && !(paid_with(cost) == want["paid"] && cost&.completed?)
        problems << "therapy #{purchase.collection&.name}" if want["therapy"] && purchase.collection&.name != want["therapy"]
        problems
      end
    end
  end
end
