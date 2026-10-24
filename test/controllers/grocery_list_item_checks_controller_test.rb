# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class GroceryListItemChecksControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    @profile = profiles(:alice)
    @list = grocery_lists(:weekly_shop) # flour (1 kg, to buy), eggs (6 pcs, in the basket); shared with Bob
    sign_in @profile
  end

  test "checking an item off buys it and restocks the ingredient" do
    item = grocery_list_items(:flour_item)

    assert_difference -> { IngredientPurchase.count }, 1 do
      post grocery_list_item_check_path(item), as: :turbo_stream
    end

    assert_response :success
    assert_predicate item.reload, :checked?
    assert_in_delta(3.5, item.ingredient.reload.quantity)
  end

  test "a checked item moves into the basket and everyone looking at the list hears about it" do
    item = grocery_list_items(:flour_item)

    assert_turbo_stream_broadcasts([ @list, @profile ], count: 2) do
      assert_turbo_stream_broadcasts([ @list, profiles(:bob) ], count: 2) do
        post grocery_list_item_check_path(item), as: :turbo_stream
      end
    end
    # The list's card, wherever Bob has his lists page open, counts what is bought.
    card = capture_turbo_stream_broadcasts([ profiles(:bob), :notifications ]).sole
    assert_equal [ "replace", "grocery_list_#{@list.id}" ], [ card["action"], card["target"] ]
    assert_includes card.to_html, "2 of 2 bought"

    body = response.body
    assert_operator body.index("disclosure"), :<, body.index("grocery_list_item_#{item.id}")
    assert_includes body, "In the basket (2)"
    assert_includes body, "Finish shopping"
  end

  test "a second tick, from a housemate or a page that was out of date, buys it once" do
    item = grocery_list_items(:flour_item)
    post grocery_list_item_check_path(item), as: :turbo_stream

    assert_no_difference -> { IngredientPurchase.count } do
      post grocery_list_item_check_path(item), as: :turbo_stream
    end
    assert_predicate item.reload, :checked?
    assert_in_delta(3.5, item.ingredient.reload.quantity)
  end

  test "unchecking takes it back, and only once" do
    item = grocery_list_items(:flour_item)
    post grocery_list_item_check_path(item), as: :turbo_stream
    delete grocery_list_item_check_path(item), as: :turbo_stream
    delete grocery_list_item_check_path(item), as: :turbo_stream

    assert_not item.reload.checked?
    assert_in_delta(2.5, item.ingredient.reload.quantity)
    assert_equal 0, IngredientPurchase.where(grocery_list_item: item).count
  end

  test "a unit that doesn't convert leaves the item unchecked and says why" do
    item = grocery_list_items(:flour_item)
    item.update!(quantity: 2, unit: units(:pcs))

    post grocery_list_item_check_path(item), as: :turbo_stream

    assert_response :unprocessable_content
    assert_not item.reload.checked?
    assert_includes response.body, "kg"
  end
end
