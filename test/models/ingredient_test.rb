# frozen_string_literal: true

require "test_helper"

class IngredientTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:alice)
  end

  test "requires a name" do
    ingredient = Ingredient.new(profile: @profile, name: nil)
    assert_not ingredient.valid?
    assert_includes ingredient.errors[:name], "can't be blank"
  end

  test "requires a profile" do
    ingredient = Ingredient.new(name: "Sugar")
    assert_not ingredient.valid?
    assert_includes ingredient.errors[:profile], "must exist"
  end

  test "quantity cannot be negative" do
    ingredient = Ingredient.new(profile: @profile, name: "Sugar", quantity: -1)
    assert_not ingredient.valid?
    assert_includes ingredient.errors[:quantity], "must be greater than or equal to 0"
  end

  test "a name finds the pantry's ingredient whatever its case and spacing" do
    assert_equal ingredients(:flour), Ingredient.find_or_create_by_name("Flour", profile_id: @profile.id)
    assert_equal ingredients(:flour), Ingredient.find_or_create_by_name("  flour  ", profile_id: @profile.id)
  end

  test "a name the pantry doesn't have makes the ingredient" do
    assert_difference -> { Ingredient.count }, 1 do
      ingredient = Ingredient.find_or_create_by_name("Sugar", profile_id: @profile.id)
      assert_equal [ "Sugar", @profile ], [ ingredient.name, ingredient.profile ]
    end
  end

  test "another profile can reuse an ingredient name" do
    ingredient = Ingredient.create!(profile: profiles(:bob), name: "Flour", quantity: 1)
    assert_equal [ "Flour", profiles(:bob) ], [ ingredient.name, ingredient.profile ]
  end

  test "a unit typed in another case is the household's own" do
    ingredient = Ingredient.new(profile: @profile, name: "Butter", quantity: 1)
    ingredient.unit_name = "KG"
    ingredient.valid?
    assert_equal units(:kg), ingredient.unit
  end

  test "a unit nobody has used yet is made on save, never on a check" do
    ingredient = Ingredient.new(profile: @profile, name: "Butter", quantity: 1)
    ingredient.unit_name = "block"
    assert_no_difference(-> { Unit.count }) { assert_predicate ingredient, :valid? }
    assert_difference(-> { Unit.count }, 1) { ingredient.save! }
    assert_equal "block", ingredient.unit.name
  end

  test "unit is optional" do
    assert_predicate Ingredient.new(profile: @profile, name: "Salt", quantity: 1), :valid?
  end

  test "two changes to one ingredient's stock at once both count, each from what the shelf holds" do
    flour = ingredients(:flour)
    before = flour.quantity
    read_by_one = Ingredient.find(flour.id)
    read_by_other = Ingredient.find(flour.id)

    read_by_one.adjust_stock!(1)
    read_by_other.adjust_stock!(1)

    assert_equal before + 2, flour.reload.quantity
    assert_equal before + 1, read_by_other.quantity, "a copy moves by its own change only"
    assert_not read_by_other.changed?
  end

  test "stock never goes below nothing on the shelf" do
    flour = ingredients(:flour)

    flour.adjust_stock!(-(flour.quantity + 5))

    assert_equal 0, flour.quantity
    assert_equal 0, flour.reload.quantity
  end

  test "an ingredient a recipe or a grocery list uses can't be deleted" do
    [ ingredients(:flour), ingredients(:eggs) ].each do |ingredient|
      assert_not ingredient.destroy, ingredient.name
      assert_predicate ingredient.errors[:base], :present?
    end
  end

  test "an ingredient field suggests the pantry's own names, by name" do
    Ingredient.create!(profile: @profile, name: "Anchovies")
    Ingredient.create!(profile: profiles(:bob), name: "Bob's anchovies")
    names = Ingredient.names_for(@profile)

    assert_equal %w[Anchovies Eggs Flour], names & %w[Flour Anchovies Eggs]
    assert_not_includes names, "Bob's anchovies"
  end

  test "an ingredient is in the \"other\" section until told otherwise" do
    assert_predicate Ingredient.create!(profile: @profile, name: "Sugar"), :other?
  end

  test "the sections, in the order of a walk through the shop" do
    assert_equal Ingredient.categories.keys.sort, Ingredient::CATEGORY_ORDER.sort
    assert_equal [ "produce", "other" ], [ Ingredient::CATEGORY_ORDER.first, Ingredient::CATEGORY_ORDER.last ]
  end

  test "a grocery list item reads its ingredient's section" do
    ingredients(:flour).update!(category: :pantry)
    assert_equal "pantry", grocery_list_items(:flour_item).category
    assert_nil GroceryListItem.new.category
  end
end
