# frozen_string_literal: true

require "test_helper"

class IngredientPurchaseTest < ActiveSupport::TestCase
  setup do
    @flour = ingredients(:flour) # 2.5 kg
    @profile = @flour.profile
  end

  def buy(quantity, **attrs)
    @flour.ingredient_purchases.create!({ profile: @profile, quantity: quantity, purchased_on: Date.new(2026, 10, 1) }.merge(attrs))
  end

  test "a purchase adds to the ingredient's stock" do
    buy(1)
    assert_in_delta(3.5, @flour.reload.quantity)
  end

  test "the purchase takes the ingredient's unit when none is given" do
    assert_equal units(:kg), buy(1).unit
  end

  test "a convertible unit is converted into the ingredient's" do
    purchase = buy(500, unit_name: "g")
    assert_in_delta(0.5, purchase.quantity)
    assert_equal units(:kg), purchase.unit
    assert_in_delta(3.0, @flour.reload.quantity)
  end

  test "an unconvertible unit is refused" do
    purchase = @flour.ingredient_purchases.new(profile: @profile, quantity: 3, purchased_on: Date.current, unit_name: "pcs")
    assert_not purchase.valid?
    assert_includes purchase.errors.full_messages_for(:unit).join, "kg"
    assert_in_delta(2.5, @flour.reload.quantity)
  end

  test "editing the quantity moves the stock by the difference" do
    purchase = buy(1)
    purchase.update!(quantity: 3)
    assert_in_delta(5.5, @flour.reload.quantity)
  end

  test "destroying a purchase takes its stock back, never below zero" do
    purchase = buy(1)
    @flour.update!(quantity: 0.4)
    purchase.destroy!
    assert_equal 0, @flour.reload.quantity
  end

  test "requires a positive quantity and a date" do
    purchase = @flour.ingredient_purchases.new(profile: @profile, quantity: 0)
    assert_not purchase.valid?
    assert purchase.errors.key?(:quantity)
    assert purchase.errors.key?(:purchased_on)
  end

  test "cost_title reads like a person would say it" do
    assert_equal "Groceries: 1 kg Flour", buy(1).cost_title
  end

  test "its cost is a groceries expense about the purchase" do
    purchase = buy(1)
    result = Transactions::SetCost.call(
      purchase, date: purchase.purchased_on, title: purchase.cost_title,
                amount: "4.5", payment_method: "card", category: :groceries
    )
    assert_equal purchase, result.cost.event.details.about
    assert_equal "groceries", result.cost.details.category
    assert_equal "expense", result.cost.details.kind
    assert_equal 450, result.cost.details.amount_cents
    assert_equal [ result.cost ], purchase.costs.to_a
  end

  test "deleting the purchase keeps its cost as an unattached expense" do
    purchase = buy(1)
    cost = Transactions::SetCost.call(
      purchase, date: purchase.purchased_on, title: "x", amount: "4.5", payment_method: "card", category: :groceries
    ).cost
    purchase.destroy!
    assert_nil cost.event.details.reload.about
  end

  test "destroying the ingredient takes its purchases with it" do
    ingredient = Ingredient.create!(profile: @profile, name: "Pepper", unit_name: "g")
    ingredient.ingredient_purchases.create!(profile: @profile, quantity: 50, purchased_on: Date.current)
    assert_difference -> { IngredientPurchase.count }, -1 do
      ingredient.destroy!
    end
  end
end
