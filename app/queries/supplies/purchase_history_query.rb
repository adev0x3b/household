# frozen_string_literal: true

module Supplies
  # A supply's purchases, the first to expire first, searched by the day
  # bought, the therapy it was bought for and where (its cost's
  # counterparty).
  class PurchaseHistoryQuery < Purchases::HistoryQuery
    private

    def listed = @scope.includes(:collection).fefo_order

    def matching(pattern)
      @scope.left_joins(:collection, :cost_details).where(<<~SQL.squish, q: pattern)
        CAST(supply_purchases.purchased_on AS TEXT) ILIKE :q
        OR collections.name ILIKE :q
        OR transaction_details.counterparty ILIKE :q
      SQL
    end
  end
end
