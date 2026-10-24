# frozen_string_literal: true

require "test_helper"

class Assistant::NameMatchTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:alice)
    @oat_milk = Ingredient.create!(profile: @profile, name: "Oat milk", quantity: 1)
  end

  def find(spoken, **options) = Assistant::NameMatch.find(@profile.ingredients, spoken, **options)

  test "an exact name wins, ignoring case and accents" do
    assert_equal ingredients(:flour), find("flour")
    assert_equal @oat_milk, find("OAT MILK", strict: true)
  end

  test "a name that is part of another matches loosely" do
    assert_equal @oat_milk, find("milk")
  end

  test "strict never lets a part of a name stand for the whole" do
    assert_nil find("milk", strict: true)
    assert_nil find("oat milk powder", strict: true)
  end

  test "strict still forgives a typo" do
    assert_equal ingredients(:flour), find("Flowr", strict: true)
  end

  test "nothing said finds nothing, and a name made of no word finds no part of one" do
    assert_nil find("  ")
    assert_nil find("!?")
    flour = ingredients(:flour)
    match = Assistant::NameMatch.new(@profile.ingredients, "flour")
    assert_queries_match(/FROM "ingredients"/, count: 1) { 2.times { assert_equal flour, match.record } }
  end

  test "pantry catalog creates a new ingredient for a looser name when strict" do
    catalog = Assistant::PantryCatalog.new(@profile)

    assert_equal @oat_milk, catalog.ingredient("milk")
    assert_predicate catalog.ingredient("milk", strict: true), :new_record?
  end
end
