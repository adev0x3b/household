# frozen_string_literal: true

require "test_helper"

class GroceryListItemTest < ActiveSupport::TestCase
  test "belongs to a grocery_list" do
    item = grocery_list_items(:flour_item)
    assert_equal grocery_lists(:weekly_shop), item.grocery_list
  end

  test "requires an ingredient" do
    item = GroceryListItem.new(grocery_list: grocery_lists(:weekly_shop), quantity: 1)
    assert_not item.valid?
    assert_includes item.errors[:ingredient], "can't be blank"
  end

  test "requires a positive quantity" do
    item = GroceryListItem.new(grocery_list: grocery_lists(:weekly_shop), ingredient: ingredients(:flour), quantity: 0)
    assert_not item.valid?
    assert_includes item.errors[:quantity], "must be greater than 0"
  end

  test "a quantity is optional" do
    item = GroceryListItem.new(grocery_list: grocery_lists(:weekly_shop), ingredient_name: "Butter")
    assert_predicate item, :valid?, item.errors.full_messages.to_sentence
  end

  test "enforces unique ingredient per grocery_list" do
    duplicate = GroceryListItem.new(grocery_list: grocery_lists(:weekly_shop), ingredient: ingredients(:flour),
                                    quantity: 1)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:ingredient_id], "has already been taken"
  end

  test "ingredient_name= makes a new ingredient in the list owner's catalog: on save, never on a check" do
    item = GroceryListItem.new(grocery_list: grocery_lists(:weekly_shop), quantity: 1)
    item.ingredient_name = "Brand New Ingredient"
    assert_no_difference(-> { Ingredient.count }) { assert_predicate item, :valid? }
    assert_difference(-> { Ingredient.count }, 1) { item.save! }
    assert_equal grocery_lists(:weekly_shop).profile, item.ingredient.profile
  end

  # ── #check! / #uncheck! ──────────────────────────────────────────────

  test "check! marks the item checked and restocks the ingredient" do
    item = grocery_list_items(:flour_item) # fixture starts unchecked
    ingredient = item.ingredient
    starting_quantity = ingredient.quantity

    item.check!

    assert_predicate item, :checked?
    assert_not_nil item.checked_at
    assert_equal starting_quantity + item.quantity, ingredient.reload.quantity
  end

  test "check! is a no-op when already checked" do
    item = grocery_list_items(:eggs_item) # fixture starts checked
    ingredient = item.ingredient
    starting_quantity = ingredient.quantity

    item.check!

    assert_equal starting_quantity, ingredient.reload.quantity
  end

  test "uncheck! marks the item unchecked and gives back the stock" do
    item = grocery_list_items(:eggs_item) # fixture starts checked
    ingredient = item.ingredient
    starting_quantity = ingredient.quantity

    item.uncheck!

    assert_not item.checked?
    assert_nil item.checked_at
    assert_equal starting_quantity - item.quantity, ingredient.reload.quantity
  end

  test "uncheck! is a no-op when already unchecked" do
    item = grocery_list_items(:flour_item) # fixture starts unchecked
    ingredient = item.ingredient
    starting_quantity = ingredient.quantity

    item.uncheck!

    assert_equal starting_quantity, ingredient.reload.quantity
  end

  test "check! records a purchase on the ingredient's owner" do
    item = grocery_list_items(:flour_item)

    assert_difference -> { IngredientPurchase.count }, 1 do
      item.check!
    end

    purchase = IngredientPurchase.order(:id).last
    assert_equal item, purchase.grocery_list_item
    assert_equal item.ingredient.profile_id, purchase.profile_id
    assert_equal item.quantity, purchase.quantity
    assert_equal Date.current, purchase.purchased_on
  end

  test "uncheck! removes the purchase check! made and takes the stock back" do
    item = grocery_list_items(:flour_item)
    ingredient = item.ingredient
    starting_quantity = ingredient.quantity

    item.check!
    assert_difference -> { IngredientPurchase.count }, -1 do
      item.uncheck!
    end

    assert_equal starting_quantity, ingredient.reload.quantity
  end

  test "check! and uncheck! of an item with no quantity only tick it" do
    item = grocery_list_items(:flour_item)
    item.update!(quantity: nil)
    starting_quantity = item.ingredient.quantity

    assert_no_difference -> { IngredientPurchase.count } do
      item.check!
    end
    assert_predicate item, :checked?
    assert_equal starting_quantity, item.ingredient.reload.quantity

    item.uncheck!
    assert_not item.checked?
    assert_equal starting_quantity, item.ingredient.reload.quantity
  end

  test "check! converts the item's unit into the ingredient's" do
    item = grocery_list_items(:flour_item)
    item.update!(quantity: 500, unit: Unit.find_or_create_by_name("g", household_id: item.grocery_list.profile.household_id))

    item.check!

    assert_in_delta(3.0, item.ingredient.reload.quantity)
  end

  test "check! refuses a unit that doesn't convert and leaves the item unchecked" do
    item = grocery_list_items(:flour_item)
    item.update!(quantity: 2, unit: units(:pcs))

    assert_raises(ActiveRecord::RecordInvalid) { item.check! }

    assert_not item.reload.checked?
    assert_in_delta(2.5, item.ingredient.reload.quantity)
  end
end
