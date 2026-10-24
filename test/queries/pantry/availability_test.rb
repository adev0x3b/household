# frozen_string_literal: true

require "test_helper"

class Pantry::AvailabilityTest < ActiveSupport::TestCase
  setup do
    @cook = profiles(:alice)
    @flour = ingredients(:flour)
  end

  def lines(recipe, profile = @cook) = Pantry::Availability.new(profile).for([ recipe ])

  test "covered ingredients are ok" do
    assert_equal [ :ok ], lines(recipe_with(@cook, "Bread", [ "Flour", 500, "g" ])).map(&:status)
  end

  test "partial stock is low and reports the shortfall in the pantry unit" do
    line = lines(recipe_with(@cook, "Big bread", [ "Flour", 3, "kg" ])).sole
    assert_equal :low, line.status
    assert_equal BigDecimal("0.5"), line.shortfall
  end

  test "empty stock is out" do
    @flour.update!(quantity: 0)
    assert_equal :out, lines(recipe_with(@cook, "Bread", [ "Flour", 1, "kg" ])).sole.status
  end

  test "an ingredient not in the pantry is out" do
    line = lines(recipe_with(@cook, "Truffle toast", [ "Truffle", 1, "pcs" ]), profiles(:bob)).sole
    assert_equal :out, line.status
    assert_nil line.ingredient
    assert_equal 1, line.shortfall
  end

  test "units that cannot convert are unknown, never a warning" do
    line = lines(recipe_with(@cook, "Egg grams", [ "Eggs", 100, "g" ])).sole
    assert_equal :unknown, line.status
    assert_not line.short?
  end

  test "the viewer's pantry is used, not the recipe owner's" do
    recipe = recipe_with(@cook, "Bread", [ "Flour", 500, "g" ])
    assert_equal :out, lines(recipe, profiles(:bob)).sole.status
  end

  test "for_meal sums the same ingredient across recipes" do
    a = recipe_with(@cook, "A", [ "Flour", 1.5, "kg" ])
    b = recipe_with(@cook, "B", [ "Flour", 1500, "g" ])
    need = Pantry::Availability.new(@cook).for_meal([ a, b ]).sole

    assert_equal BigDecimal("3.0"), need.needed
    assert_equal :low, need.status
  end

  test "short? reflects any short line" do
    assert Pantry::Availability.new(@cook).short?([ recipe_with(@cook, "Big", [ "Flour", 9, "kg" ]) ])
    assert_not Pantry::Availability.new(@cook).short?([ recipe_with(@cook, "Small", [ "Flour", 1, "kg" ]) ])
  end
end
