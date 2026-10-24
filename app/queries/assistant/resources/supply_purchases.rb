# frozen_string_literal: true

module Assistant
  module Resources
    class SupplyPurchases < Resource
      def key = "supply_purchase"
      def model = SupplyPurchase
      def search_columns = %w[supplies.name]
      def writable = %w[quantity_purchased quantity_remaining purchased_on expires_on opened_on collection_id]
      def date_column = :purchased_on

      def scope(profile) = SupplyPurchase.where(id: SupplyPurchase.accessible_by(profile).select(:id)).joins(:supply)

      # Its owner, and whoever its therapy is shared with.
      def readers(purchase) = [ purchase.profile, *purchase.collection&.shared_profiles ]

      def summaries(purchases, _profile)
        purchases.map do |purchase|
          cost = purchase.cost
          { supply: purchase.supply.name, supply_id: purchase.supply_id, collection: purchase.collection&.name,
            date: purchase.purchased_on.iso8601, quantity: purchase.quantity_purchased.to_s, remaining: purchase.quantity_remaining.to_s,
            expires_on: purchase.expires_on&.iso8601, cost: money(cost), cost_id: cost&.id }
        end
      end

      private

      def read_for_summaries(purchases)
        super
        load(purchases, :supply, :collection)
      end
    end
  end
end
