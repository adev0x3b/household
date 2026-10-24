# frozen_string_literal: true

require "test_helper"

class RecipeShareTest < ActiveSupport::TestCase
  test "belongs to a recipe and a profile" do
    share = recipe_shares(:roast_chicken_bob)
    assert_equal recipes(:roast_chicken), share.recipe
    assert_equal profiles(:bob), share.profile
  end

  test "enforces unique profile per recipe" do
    duplicate = RecipeShare.new(recipe: recipes(:roast_chicken), profile: profiles(:bob))
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:profile_id], "has already been taken"
  end

  test "cannot share a recipe with its own owner" do
    share = RecipeShare.new(recipe: recipes(:roast_chicken), profile: profiles(:alice))
    assert_not share.valid?
    assert_includes share.errors[:profile_id], "is invalid"
  end
end
