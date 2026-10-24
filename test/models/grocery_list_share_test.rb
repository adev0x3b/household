# frozen_string_literal: true

require "test_helper"

class GroceryListShareTest < ActiveSupport::TestCase
  test "belongs to a grocery_list and a profile" do
    share = grocery_list_shares(:weekly_shop_bob)
    assert_equal grocery_lists(:weekly_shop), share.grocery_list
    assert_equal profiles(:bob), share.profile
  end

  test "enforces unique profile per grocery_list" do
    duplicate = GroceryListShare.new(grocery_list: grocery_lists(:weekly_shop), profile: profiles(:bob))
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:profile_id], "has already been taken"
  end

  test "cannot share a grocery_list with its own owner" do
    share = GroceryListShare.new(grocery_list: grocery_lists(:weekly_shop), profile: profiles(:alice))
    assert_not share.valid?
    assert_includes share.errors[:profile_id], "is invalid"
  end
end
