# frozen_string_literal: true

require "test_helper"

class GroceryLists::AislesTest < ActiveSupport::TestCase
  test "what is left to buy comes by section in the order of the walk, and by name within one" do
    items = [ item("Soap", :household), item("milk", :dairy_eggs), item("Apples", :produce),
              item("Butter", :dairy_eggs), item("Eggs", :dairy_eggs, checked_at: 1.hour.ago) ]
    aisles = GroceryLists::Aisles.new(items)

    assert_equal %w[produce dairy_eggs household], aisles.to_buy.map(&:category)
    assert_equal %w[Butter milk], names(aisles.to_buy.second.items)
  end

  test "the basket shows the last item picked up first, and a tie by the item" do
    now = Time.current
    items = [ item("Bread", :bakery, id: 1, checked_at: now - 1.hour), item("Milk", :dairy_eggs, id: 2, checked_at: now),
              item("Jam", :pantry, id: 3, checked_at: now - 1.hour), item("Flour", :pantry, id: 4) ]
    aisles = GroceryLists::Aisles.new(items)

    assert_equal %w[Milk Jam Bread], names(aisles.in_basket)
    assert_equal [ "pantry" ], aisles.to_buy.map(&:category)
  end

  test "a list with no items has no aisles" do
    assert_predicate GroceryLists::Aisles.new([]), :empty?
    assert_not_predicate grocery_lists(:weekly_shop).aisles, :empty?
  end

  private

  def names(items) = items.map { |item| item.ingredient.name }

  def item(name, category, id: nil, checked_at: nil)
    GroceryListItem.new(id: id, ingredient: Ingredient.new(name: name, category: category), checked: checked_at.present?, checked_at: checked_at)
  end
end
