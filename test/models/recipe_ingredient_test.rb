# frozen_string_literal: true

require "test_helper"

class RecipeIngredientTest < ActiveSupport::TestCase
  test "belongs to a recipe" do
    entry = recipe_ingredients(:chicken_flour)
    assert_equal recipes(:roast_chicken), entry.recipe
  end

  test "requires an ingredient" do
    entry = RecipeIngredient.new(recipe: recipes(:roast_chicken), quantity: 1)
    assert_not entry.valid?
    assert_includes entry.errors[:ingredient], "can't be blank"
  end

  test "requires a positive quantity" do
    entry = RecipeIngredient.new(recipe: recipes(:roast_chicken), ingredient: ingredients(:flour), quantity: 0)
    assert_not entry.valid?
    assert_includes entry.errors[:quantity], "must be greater than 0"
  end

  test "enforces unique ingredient per recipe" do
    duplicate = RecipeIngredient.new(recipe: recipes(:roast_chicken), ingredient: ingredients(:flour), quantity: 1)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:ingredient_id], "has already been taken"
  end

  test "allows the same ingredient across different recipes" do
    pancakes = Recipe.create!(profile: profiles(:alice), name: "Pancakes")
    entry = RecipeIngredient.new(recipe: pancakes, ingredient: ingredients(:flour), quantity: 1)
    assert_predicate entry, :valid?
  end

  test "only uses the recipe owner's ingredients" do
    entry = RecipeIngredient.new(recipe: recipes(:pancakes), ingredient: ingredients(:flour), quantity: 1)
    assert_not entry.valid?
    assert_includes entry.errors[:ingredient], "isn't one you have access to"
  end

  test "ingredient_name= resolves to an existing ingredient idempotently" do
    entry = RecipeIngredient.new(recipe: recipes(:roast_chicken), quantity: 1)
    entry.ingredient_name = "flour" # different case than the fixture's "Flour"
    entry.valid?
    assert_equal ingredients(:flour), entry.ingredient
  end

  test "ingredient_name= makes a new ingredient in the recipe owner's catalog when none matches: on save, never on a check" do
    entry = RecipeIngredient.new(recipe: recipes(:roast_chicken), quantity: 1)
    entry.ingredient_name = "Brand New Ingredient"
    assert_no_difference(-> { Ingredient.count }) { assert_predicate entry, :valid? }
    assert_difference(-> { Ingredient.count }, 1) { entry.save! }
    assert_equal "Brand New Ingredient", entry.ingredient.name
    assert_equal recipes(:roast_chicken).profile, entry.ingredient.profile
  end

  test "unit_name= resolves to an existing unit idempotently" do
    entry = RecipeIngredient.new(recipe: recipes(:roast_chicken), ingredient: ingredients(:eggs), quantity: 2)
    entry.unit_name = "PCS"
    entry.valid?
    assert_equal units(:pcs), entry.unit
  end

  test "unit is optional" do
    entry = RecipeIngredient.new(recipe: recipes(:roast_chicken), ingredient: ingredients(:eggs), quantity: 2)
    assert_predicate entry, :valid?
  end
end
