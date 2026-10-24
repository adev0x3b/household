# frozen_string_literal: true

require "test_helper"

class GroceryLists::ParseItemTest < ActiveSupport::TestCase
  UNITS = %w[kg pcs l].freeze

  def parse(text) = GroceryLists::ParseItem.call(text, unit_names: UNITS)

  test "quantity and unit before the name" do
    result = parse("2 kg flour")
    assert_equal [ "flour", 2, "kg" ], [ result.name, result.quantity, result.unit_name ]
  end

  test "quantity and unit after the name" do
    result = parse("flour 2 kg")
    assert_equal [ "flour", 2, "kg" ], [ result.name, result.quantity, result.unit_name ]
  end

  test "a unit glued to its number" do
    result = parse("2kg flour")
    assert_equal [ "flour", 2, "kg" ], [ result.name, result.quantity, result.unit_name ]

    result = parse("flour 2kg")
    assert_equal [ "flour", 2, "kg" ], [ result.name, result.quantity, result.unit_name ]
  end

  test "a number alone is the quantity and the next word belongs to the name" do
    result = parse("6 eggs")
    assert_equal [ "eggs", 6, nil ], [ result.name, result.quantity, result.unit_name ]

    result = parse("eggs 6")
    assert_equal [ "eggs", 6, nil ], [ result.name, result.quantity, result.unit_name ]
  end

  test "a decimal comma is a decimal" do
    result = parse("1,5 l milk")
    assert_equal [ "milk", BigDecimal("1.5"), "l" ], [ result.name, result.quantity, result.unit_name ]
  end

  test "a name alone" do
    result = parse("flour")
    assert_equal [ "flour", nil, nil ], [ result.name, result.quantity, result.unit_name ]
  end

  test "the metric units work before the household has typed them" do
    result = parse("500 g rice")
    assert_equal [ "rice", 500, "g" ], [ result.name, result.quantity, result.unit_name ]
  end

  test "a name of several words keeps them all" do
    result = parse("olive oil 500 ml")
    assert_equal [ "olive oil", 500, "ml" ], [ result.name, result.quantity, result.unit_name ]

    result = parse("extra virgin olive oil")
    assert_equal [ "extra virgin olive oil", nil, nil ], [ result.name, result.quantity, result.unit_name ]
  end

  test "an unknown word next to the number stays in the name" do
    result = parse("2 bags flour")
    assert_equal [ "bags flour", 2, nil ], [ result.name, result.quantity, result.unit_name ]
  end

  test "blank is an empty name" do
    assert_equal "", parse("   ").name
    assert_equal "", parse(nil).name
  end
end
