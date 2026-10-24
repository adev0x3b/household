# frozen_string_literal: true

require "test_helper"

class GroceryListTest < ActiveSupport::TestCase
  test "belongs to a profile" do
    list = grocery_lists(:weekly_shop)
    assert_equal profiles(:alice), list.profile
  end

  test "requires a name" do
    list = GroceryList.new(profile: profiles(:alice), name: nil)
    assert_not list.valid?
    assert_includes list.errors[:name], "can't be blank"
  end

  test "has default status of active" do
    list = GroceryList.new
    assert_equal "active", list.status
  end

  test "status enum values" do
    expected = { "active" => 0, "completed" => 1 }
    assert_equal expected, GroceryList.statuses
  end

  test "destroying a list destroys its items and shares" do
    list = grocery_lists(:weekly_shop)
    item = grocery_list_items(:flour_item)
    share = grocery_list_shares(:weekly_shop_bob)

    list.destroy!

    assert_not GroceryListItem.exists?(item.id)
    assert_not GroceryListShare.exists?(share.id)
  end

  test "accessible_by returns lists owned by the profile" do
    assert_includes GroceryList.accessible_by(profiles(:alice)), grocery_lists(:weekly_shop)
  end

  test "accessible_by returns lists shared with the profile" do
    assert_includes GroceryList.accessible_by(profiles(:bob)), grocery_lists(:weekly_shop)
  end

  test "accessible_by excludes lists neither owned nor shared" do
    assert_not_includes GroceryList.accessible_by(profiles(:carol)), grocery_lists(:weekly_shop)
  end

  test "rejects duplicate ingredients submitted together" do
    list = GroceryList.new(profile: profiles(:alice), name: "Extra shop")
    list.grocery_list_items.build(ingredient: ingredients(:eggs), quantity: 2)
    list.grocery_list_items.build(ingredient: ingredients(:eggs), quantity: 3)

    assert_not list.valid?
    assert_includes list.errors[:grocery_list_items], "can't include the same ingredient more than once (Eggs)"
  end
end

class GroceryListShoppingTest < ActiveSupport::TestCase
  setup do
    @list = grocery_lists(:weekly_shop) # flour (to buy), eggs (in the basket)
  end

  test "counts what is bought" do
    assert_equal 2, @list.total_count
    assert_equal 1, @list.checked_count
    assert_not @list.all_bought?

    grocery_list_items(:flour_item).check!
    assert_predicate @list.reload, :all_bought?
  end

  test "an empty list is never all bought" do
    assert_not GroceryList.new(profile: profiles(:alice), name: "Nothing").all_bought?
  end

  test "finish! completes the list" do
    @list.finish!
    assert_predicate @list.reload, :completed?
  end

  test "reopen! puts everything back on the list and keeps what was bought" do
    eggs = grocery_list_items(:eggs_item)
    purchase = eggs.ingredient.ingredient_purchases.create!(profile: profiles(:alice), quantity: 6, unit: units(:pcs), purchased_on: Date.current, grocery_list_item: eggs)
    stock = eggs.ingredient.reload.quantity
    @list.finish!

    assert_no_difference -> { IngredientPurchase.count } do
      @list.reopen!
    end

    assert_predicate @list.reload, :active?
    assert_not eggs.reload.checked?
    assert_nil eggs.checked_at
    assert_nil purchase.reload.grocery_list_item_id
    assert_equal stock, eggs.ingredient.reload.quantity
  end

  test "after reopening, unchecking only takes back the new purchase" do
    eggs = grocery_list_items(:eggs_item)
    old_purchase = eggs.ingredient.ingredient_purchases.create!(profile: profiles(:alice), quantity: 6, unit: units(:pcs), purchased_on: Date.current, grocery_list_item: eggs)
    @list.reopen!

    eggs.reload.check!
    assert_equal 1, eggs.ingredient_purchases.count

    eggs.uncheck!
    assert IngredientPurchase.exists?(old_purchase.id)
    assert_equal 0, eggs.ingredient_purchases.count
  end

  test "newest_first works with accessible_by" do
    newer = GroceryList.create!(profile: profiles(:alice), name: "Later")
    assert_equal newer, GroceryList.accessible_by(profiles(:alice)).newest_first.first
  end
end
