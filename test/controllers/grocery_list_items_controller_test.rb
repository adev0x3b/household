# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class GroceryListItemsControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    @profile = profiles(:alice)
    @list = grocery_lists(:weekly_shop) # flour (1 kg, to buy), eggs (6 pcs, in the basket); shared with profile two
    sign_in @profile
  end

  # --- quick-add -----------------------------------------------------------------

  test "adding '2 kg butter' puts a new ingredient on the list with its quantity and unit" do
    assert_difference [ -> { @list.grocery_list_items.count }, -> { Ingredient.count } ], 1 do
      post grocery_list_grocery_list_items_path(@list), params: { grocery_list_item: { text: "2 kg butter" } }, as: :turbo_stream
    end

    assert_response :success
    item = @list.grocery_list_items.joins(:ingredient).find_by(ingredients: { name: "butter" })
    assert_equal 2, item.quantity
    assert_equal "kg", item.unit.name
    assert_includes response.body, %(target="grocery_list-#{@list.id}-items")
    assert_includes response.body, %(target="grocery_list-#{@list.id}-header")
    # Never the bar being typed into: it keeps its focus.
    assert_not_includes response.body, "grocery-list-quick-add"
  end

  test "adding '6 eggs' uses the existing ingredient and takes the number as the quantity" do
    @list.grocery_list_items.destroy_all

    assert_no_difference -> { Ingredient.count } do
      post grocery_list_grocery_list_items_path(@list), params: { grocery_list_item: { text: "6 eggs" } }, as: :turbo_stream
    end

    item = @list.grocery_list_items.reload.sole
    assert_equal ingredients(:eggs), item.ingredient
    assert_equal 6, item.quantity
    assert_nil item.unit
  end

  test "adding a name alone puts it on the list without a quantity" do
    post grocery_list_grocery_list_items_path(@list), params: { grocery_list_item: { text: "Honey" } }, as: :turbo_stream

    assert_response :success
    assert_nil @list.grocery_list_items.joins(:ingredient).find_by(ingredients: { name: "Honey" }).quantity
  end

  test "an item already on the list is refused with a word, not added twice" do
    assert_no_difference -> { @list.grocery_list_items.count } do
      post grocery_list_grocery_list_items_path(@list), params: { grocery_list_item: { text: "flour" } }, as: :turbo_stream
    end

    assert_response :unprocessable_content
    assert_includes response.body, "Flour is already on the list."
  end

  test "a blank line is refused" do
    assert_no_difference -> { @list.grocery_list_items.count } do
      post grocery_list_grocery_list_items_path(@list), params: { grocery_list_item: { text: "  " } }, as: :turbo_stream
    end

    assert_response :unprocessable_content
  end

  test "a housemate adds to a shared list, a stranger can't" do
    sign_in profiles(:bob)
    post grocery_list_grocery_list_items_path(@list), params: { grocery_list_item: { text: "milk" } }, as: :turbo_stream
    assert_response :success

    sign_in profiles(:carol)
    assert_no_difference -> { @list.grocery_list_items.count } do
      post grocery_list_grocery_list_items_path(@list), params: { grocery_list_item: { text: "sugar" } }, as: :turbo_stream
    end
  end

  # --- edit / update / destroy -----------------------------------------------------

  test "edit opens the item's modal" do
    get edit_grocery_list_item_path(grocery_list_items(:flour_item)), as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'name="grocery_list_item[unit_name]"'
    assert_includes response.body, 'name="grocery_list_item[category]"'
  end

  test "update changes how much, in what, and the ingredient's store section" do
    item = grocery_list_items(:flour_item)

    patch grocery_list_item_path(item), params: { grocery_list_item: { quantity: "3", unit_name: "kg", category: "pantry" } },
                                        headers: submitted_from(grocery_list_path(@list))

    assert_redirected_to grocery_list_path(@list)
    assert_equal 3, item.reload.quantity
    assert_equal "pantry", item.ingredient.reload.category
    follow_redirect!
    assert_toast "Flour updated."
  end

  test "destroy takes the item off the list and names it" do
    item = grocery_list_items(:flour_item)

    assert_difference -> { @list.grocery_list_items.count }, -1 do
      delete grocery_list_item_path(item), as: :turbo_stream
    end

    assert_response :success
    assert_includes response.body, "Flour removed from the list."
    assert_includes response.body, %(target="grocery_list-#{@list.id}-items")
  end
end
