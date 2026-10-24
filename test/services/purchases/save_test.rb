# frozen_string_literal: true

require "test_helper"

class Purchases::SaveTest < ActiveSupport::TestCase
  setup do
    @flour = ingredients(:flour) # 2.5 kg
    @profile = @flour.profile
  end

  test "a purchase and what it cost are saved together, the cost paid on its date" do
    result = save(build, cost: { amount: "4.50", payment_method: "card" })

    assert_predicate result, :success?
    cost = result.record.costs.sole
    assert_equal [ Date.new(2026, 10, 1), "groceries", 450 ], [ cost.date, cost.details.category, cost.details.amount_cents ]
    assert_predicate cost, :completed?
    assert_in_delta(3.5, @flour.reload.quantity)
  end

  test "no amount, no cost" do
    result = save(build, cost: { amount: "", payment_method: "card" })

    assert_predicate result, :success?
    assert_empty result.record.costs
  end

  test "a cost that can't be saved takes the purchase back, and the form gets a new record with its errors" do
    result = nil
    assert_no_difference [ -> { IngredientPurchase.count }, -> { Transaction.count } ] do
      result = save(build, cost: { amount: "4.50", payment_method: "" })
    end

    assert_predicate result, :failure?
    assert_predicate result.record, :new_record?, "a rolled-back save still says persisted?: the form needs a record it can post again"
    assert_predicate result.record.errors, :any?
    assert_in_delta(2.5, @flour.reload.quantity)
  end

  test "a failed update keeps what was typed and changes nothing" do
    purchase = save(build, cost: { amount: "4.50", payment_method: "card" }).record

    result = Purchases::Save.call(purchase, attributes: { quantity: 2 }, cost: { amount: "9", payment_method: "" }, category: :groceries)

    assert_predicate result, :failure?
    assert_same purchase, result.record
    assert_equal 2, result.record.quantity
    assert_equal 1, purchase.reload.quantity
    assert_equal 450, purchase.costs.sole.details.amount_cents
  end

  test "a new record needs a way to build it again" do
    assert_raises(ArgumentError) { Purchases::Save.call(build, cost: {}, category: :groceries) }
  end

  private

  def build = @flour.ingredient_purchases.new(profile: @profile, quantity: 1, purchased_on: Date.new(2026, 10, 1))

  def save(purchase, cost:) = Purchases::Save.call(purchase, cost: cost, category: :groceries) { build }
end
