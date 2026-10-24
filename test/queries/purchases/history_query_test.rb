# frozen_string_literal: true

require "test_helper"

# A purchase history's search, matched against the day bought and where.
class Purchases::HistoryQueryTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @older = ingredient_purchase!(profile: @profile, name: "Rice", purchased_on: Date.new(2026, 9, 3))
    @newer = ingredient_purchase!(profile: @profile, name: "Rice", purchased_on: Date.new(2026, 10, 1))
    Transactions::SetCost.call(@older, date: @older.purchased_on, title: "Rice", amount: "3", payment_method: "card",
                                       category: :groceries, counterpart: "Mercato Centrale")
  end

  test "without a term, every purchase, newest first" do
    assert_equal [ @newer, @older ], history.call.to_a
  end

  test "a term finds a purchase by where it was bought or by its day" do
    assert_equal [ @older ], history("mercato").call.to_a
    assert_equal [ @newer ], history("2026-10").call.to_a
    assert_empty history("100%").call
  end

  private

  def history(term = nil)
    Ingredients::PurchaseHistoryQuery.new(scope: IngredientPurchase.where(ingredient: @older.ingredient), filters: { q: term })
  end
end
