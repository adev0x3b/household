# frozen_string_literal: true

require "test_helper"

# Merging one unit spelled two ways moves everything that names the
# duplicate, the pantry's rows as well as the lab's, so the duplicate can
# go. (Ranges that collide are Assistant::UnitNameTest's.)
class Units::MergeDuplicatesTest < ActiveSupport::TestCase
  test "every table that names a unit is moved by the merge, or is the ranges it moves one at a time" do
    naming = ActiveRecord::Base.connection.tables.select do |table|
      ActiveRecord::Base.connection.foreign_keys(table).any? { |key| key.to_table == "units" }
    end

    assert_equal naming.sort, (Units::MergeDuplicates::USES.map(&:table_name) + [ "reference_ranges" ]).sort
  end

  test "the pantry's rows move to the unit kept, and the duplicate goes" do
    alice = profiles(:alice)
    keep = Unit.create!(household: alice.household, name: "10^3/µL")
    other = Unit.create!(household: alice.household, name: "K/µL")
    honey = Ingredient.create!(profile: alice, name: "Honey", quantity: 1, unit: other)
    purchase = honey.ingredient_purchases.create!(profile: alice, quantity: 1, unit: other, purchased_on: Date.current)
    line = recipe_with(alice, "Porridge", [ "Oats", 50, "K/µL" ]).recipe_ingredients.sole
    item = grocery_lists(:weekly_shop).grocery_list_items.create!(ingredient: honey, quantity: 1, unit: other)

    merged = Units::MergeDuplicates.call(Units::Duplicates::Group.new(name: "10^3/µL", keep: keep, others: [ other ]))

    assert_equal 4, merged.rows
    assert_equal [ keep ] * 4, [ honey, purchase, line, item ].map(&:reload).map(&:unit)
    assert_not Unit.exists?(other.id)
  end
end
