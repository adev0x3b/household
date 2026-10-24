# frozen_string_literal: true

module Assistant
  module Resources
    class Supplies < Resource
      def key = "supply"
      def model = Supply
      def search_columns = %i[name]
      def writable = %w[name category unit_label low_stock_threshold pao_days]
      def enums = { "category" => Supply.categories.keys }

      # Own supplies, and those bought for a collection shared with the
      # profile (Supply.accessible_by): doses are taken from that stock too.
      def scope(profile) = Supply.where(id: Supply.accessible_by(profile).select(:id))

      # Its owner, and whoever shares a therapy it was bought for.
      def readers(supply)
        shares = CollectionShare.where(collection_id: supply.supply_purchases.select(:collection_id))
        [ supply.profile, *Profile.where(id: shares.select(:profile_id)) ]
      end

      # Stock is counted only from the purchases the profile can see, all
      # of the page's supplies in one sum.
      def summaries(supplies, profile)
        in_stock = SupplyPurchase.accessible_by(profile).where(supply_id: supplies.map(&:id)).group(:supply_id).sum(:quantity_remaining)
        supplies.map do |supply|
          { name: supply.name, category: supply.category, unit: supply.unit_label, in_stock: in_stock.fetch(supply.id, 0).to_s }
        end
      end

      private

      # A supply belongs to a collection through what was bought for it.
      def filter_collection(relation, collection_id)
        relation.where(id: SupplyPurchase.where(collection_id: collection_id).select(:supply_id))
      end
    end
  end
end
