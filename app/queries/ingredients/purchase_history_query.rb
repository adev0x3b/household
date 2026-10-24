# frozen_string_literal: true

module Ingredients
  # An ingredient's purchases, newest first, searched by the day bought and
  # where (its cost's counterparty).
  class PurchaseHistoryQuery < Purchases::HistoryQuery
    private

    def listed = @scope.includes(:unit).latest_first

    def matching(pattern)
      @scope.left_joins(:cost_details).where(<<~SQL.squish, q: pattern)
        CAST(ingredient_purchases.purchased_on AS TEXT) ILIKE :q
        OR transaction_details.counterparty ILIKE :q
      SQL
    end
  end
end
