# frozen_string_literal: true

require "test_helper"

# A catalog row named on a form ("Saffron" on a recipe line, "pinch" next
# to it) is looked up while the record is checked and made only when it is
# saved: checking writes nothing, and a refused save leaves nothing behind.
class TypedNamesTest < ActiveSupport::TestCase
  CATALOG = %w[Ingredient.count Unit.count Analyte.count].freeze

  setup { @alice = profiles(:alice) }

  test "a recipe line: checking it writes nothing, saving it adds what is new to its owner's catalog" do
    line = recipes(:roast_chicken).recipe_ingredients.build(ingredient_name: "Saffron", quantity: 1, unit_name: "pinch")
    assert_no_difference(CATALOG) { assert_predicate line, :valid? }
    assert_equal "Saffron", line.ingredient.name

    assert_difference [ "Ingredient.count", "Unit.count" ], 1 do
      line.save!
    end
    assert_equal [ @alice.id, "Saffron" ], [ line.ingredient.profile_id, line.ingredient.name ]
    assert_equal [ @alice.household_id, "pinch" ], [ line.unit.household_id, line.unit.name ]
  end

  test "a name already in the catalog is that row, whatever its case and spacing" do
    line = recipes(:roast_chicken).recipe_ingredients.build(ingredient_name: " eggs ", quantity: 2, unit_name: "PCS")
    assert_no_difference(CATALOG) { line.save! }
    assert_equal [ ingredients(:eggs), units(:pcs) ], [ line.ingredient, line.unit ]
  end

  test "a refused save leaves nothing in the catalog, and the form still shows what was typed" do
    item = grocery_lists(:weekly_shop).grocery_list_items
      .build(ingredient_name: "Capers", unit_name: "jar", quantity: -1)
    assert_no_difference(CATALOG) { assert_not item.save }
    assert_equal [ "Capers", "jar" ], [ item.ingredient.name, item.unit.name ]
  end

  test "an emptied name names nothing: the unit a line had is taken off it" do
    item = grocery_lists(:weekly_shop).grocery_list_items.create!(ingredient_name: "Capers", unit_name: "jar", quantity: 1)
    item.update!(unit_name: "")
    assert_nil item.reload.unit

    ingredient = Ingredient.create!(profile: @alice, name: "Rice", unit_name: "bag")
    ingredient.update!(unit_name: " ")
    assert_nil ingredient.reload.unit
  end

  test "a name typed and then emptied before the save names nothing" do
    item = grocery_lists(:weekly_shop).grocery_list_items.build(ingredient_name: "Capers", unit_name: "jar", quantity: 1)
    item.unit_name = ""

    assert_no_difference("Unit.count") { item.save! }
    assert_nil item.unit
  end

  test "a row given after the save is kept: the name typed before is spent" do
    item = grocery_lists(:weekly_shop).grocery_list_items.create!(ingredient_name: "Capers", unit_name: "jar", quantity: 1)
    item.update!(unit: units(:kg))

    assert_equal units(:kg), item.reload.unit
  end

  test "a lab value's analyte and unit, and an ingredient's unit, are made on save, never on a check" do
    report = lab_result!(profile: @alice, date: Date.new(2026, 9, 16))
    entry = report.lab_test_result_entries.build(analyte_name: "Ferritin", unit_name: "ng/mL", value: "")
    assert_no_difference(CATALOG) { assert_not entry.save }
    entry.value = "80"
    assert_difference [ "Analyte.count", "Unit.count" ], 1 do
      entry.save!
    end

    ingredient = Ingredient.new(profile: @alice, name: "Rice", unit_name: "bag")
    assert_no_difference("Unit.count") { assert_predicate ingredient, :valid? }
    assert_difference("Unit.count", 1) { ingredient.save! }
  end

  test "grams of something kept in kilograms are counted in kilograms, adding no unit for the grams" do
    purchase = IngredientPurchase.new(ingredient: ingredients(:flour), profile: @alice, quantity: 500, unit_name: "g",
                                      purchased_on: Date.current)
    assert_no_difference("Unit.count") { purchase.save! }
    assert_equal [ 0.5, units(:kg) ], [ purchase.quantity.to_f, purchase.unit ]
  end

  test "a recipe's lines read their names in one query, and make the new ones in one statement" do
    recipe = Recipe.new(profile: @alice, name: "Crêpes")
    lines = [ %w[flour g], %w[EGGS pcs], %w[Saffron pinch], %w[Fennel pinch] ].map do |name, unit|
      recipe.recipe_ingredients.build(ingredient_name: name, quantity: 1, unit_name: unit)
    end

    assert_queries_match(/FROM "ingredients" WHERE .*LOWER\(name\) IN/, count: 1) do
      assert_no_difference(CATALOG) { assert_predicate recipe, :valid? }
    end
    assert_equal [ ingredients(:flour), ingredients(:eggs) ], lines.first(2).map(&:ingredient)
    assert(lines.last(2).all? { _1.ingredient.new_record? })

    assert_queries_match(/INSERT INTO "ingredients"/, count: 1) do
      assert_difference -> { @alice.ingredients.count } => 2, -> { Unit.count } => 2 do # pinch, and g
        recipe.save!
      end
    end
    assert_equal(%w[Flour Eggs Saffron Fennel], lines.map { _1.reload.ingredient.name })
    assert_equal 1, lines.last(2).map(&:unit_id).uniq.size, "the two lines name one new unit"
  end

  test "many names at once: the missing made in one statement, the rest found whatever their case" do
    rows = nil
    assert_difference -> { @alice.ingredients.count }, 2 do
      rows = Ingredient.find_or_create_all_by_name([ " Flour ", "flour", "Capers", "capers ", "Dill", "" ], profile_id: @alice.id)
    end
    assert_equal %w[capers dill flour], rows.keys.sort
    assert_equal ingredients(:flour), rows["flour"]
    assert_equal [ "Capers", @alice.id ], [ rows["capers"].name, rows["capers"].profile_id ]
    assert_equal({}, Ingredient.find_or_create_all_by_name([ " " ], profile_id: @alice.id))
  end

  test "two saves racing for the same new name end with one row, each pointing at it" do
    first = Unit.find_or_create_by_name("cup", household_id: @alice.household_id)
    Unit.transaction do
      swapping(Unit, :named, ->(*) { nil }) do # as if the other save hadn't committed when this one looked
        assert_equal first, Unit.find_or_create_by_name("Cup", household_id: @alice.household_id)
      end
      assert Unit.exists?(first.id), "the transaction it ran in goes on"
    end
  end

  test "a new name another save made after this one was checked is that row, not a second one" do
    item = grocery_lists(:weekly_shop).grocery_list_items.build(ingredient_name: "Capers", unit_name: "jar", quantity: 1)
    assert_predicate item, :valid?
    assert_predicate item.unit, :new_record?, "checked while nobody had a jar"

    other = Unit.find_or_create_by_name("jar", household_id: @alice.household_id)
    assert_no_difference("Unit.count") { item.save! }
    assert_equal other, item.unit
  end
end
