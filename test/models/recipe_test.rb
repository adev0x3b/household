# frozen_string_literal: true

require "test_helper"

class RecipeTest < ActiveSupport::TestCase
  test "belongs to a profile" do
    recipe = recipes(:roast_chicken)
    assert_equal profiles(:alice), recipe.profile
  end

  test "requires a name" do
    recipe = Recipe.new(profile: profiles(:alice), name: nil)
    assert_not recipe.valid?
    assert_includes recipe.errors[:name], "can't be blank"
  end

  test "destroying a recipe destroys its steps, ingredients, and shares" do
    recipe = recipes(:roast_chicken)
    step = recipe_steps(:roast_chicken_first)
    entry = recipe_ingredients(:chicken_flour)
    share = recipe_shares(:roast_chicken_bob)

    recipe.destroy!

    assert_not RecipeStep.exists?(step.id)
    assert_not RecipeIngredient.exists?(entry.id)
    assert_not RecipeShare.exists?(share.id)
  end

  test "a meal is made of the person's own recipes and those shared with them, by name" do
    assert_equal [ recipes(:pancakes), recipes(:roast_chicken) ], Recipe.choices_for(profiles(:bob)).to_a
    assert_equal [ recipes(:roast_chicken) ], Recipe.choices_for(profiles(:alice)).to_a
  end

  test "accessible_by returns recipes owned by the profile" do
    assert_includes Recipe.accessible_by(profiles(:alice)), recipes(:roast_chicken)
  end

  test "accessible_by returns recipes shared with the profile" do
    assert_includes Recipe.accessible_by(profiles(:bob)), recipes(:roast_chicken)
  end

  test "accessible_by excludes recipes neither owned nor shared" do
    assert_not_includes Recipe.accessible_by(profiles(:carol)), recipes(:roast_chicken)
  end

  test "renumbers step positions from submission order, skipping destroyed rows" do
    recipe = recipes(:roast_chicken)
    recipe.recipe_steps.load # cache the target array so mark_for_destruction below is visible to it
    first_step = recipe.recipe_steps.min_by(&:position)
    first_step.mark_for_destruction
    recipe.recipe_steps.build(instruction: "Let it rest for 10 minutes.")

    recipe.valid?

    survivors = recipe.recipe_steps.reject(&:marked_for_destruction?).sort_by(&:position)
    assert_equal [ 1, 2 ], survivors.map(&:position)
  end

  test "rejects duplicate ingredients submitted together" do
    recipe = Recipe.new(profile: profiles(:alice), name: "Omelette")
    recipe.recipe_ingredients.build(ingredient: ingredients(:eggs), quantity: 2)
    recipe.recipe_ingredients.build(ingredient: ingredients(:eggs), quantity: 3)

    assert_not recipe.valid?
    assert_includes recipe.errors[:recipe_ingredients], "can't include the same ingredient more than once (Eggs)"
  end
end
