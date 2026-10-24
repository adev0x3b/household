# frozen_string_literal: true

module Assistant
  module Resources
    # A few series grouped as one thing: a therapy, a job hunt, a renovation.
    class Collections < Resource
      def key = "collection"
      def model = Collection
      def search_columns = %i[name notes]
      def writable = %w[name notes status section]
      def enums = { "status" => Collection.statuses.keys, "section" => Collection::SECTIONS }

      def scope(profile) = Collection.where(id: Collection.accessible_by(profile).select(:id))

      # Each with the supplies bought for it, read for the page in one query.
      def summaries(collections, profile)
        bought = SupplyPurchase.accessible_by(profile).where(collection_id: collections.map(&:id)).joins(:supply).distinct
          .order("supplies.name").pluck(:collection_id, "supplies.id", "supplies.name").group_by(&:first)
        collections.map do |collection|
          { name: collection.name, section: collection.section, status: collection.status, notes: collection.notes.presence&.truncate(120),
            supplies: Array(bought[collection.id]).map { |_, id, name| { id: id, name: name } } }
        end
      end
    end
  end
end
