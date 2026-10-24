# frozen_string_literal: true

require "test_helper"

class GroceryListCompletionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @profile = profiles(:alice)
    @list = grocery_lists(:weekly_shop) # flour to buy, eggs in the basket; shared with Bob
    sign_in @profile
  end

  test "finishing completes the list and comes back to it" do
    post grocery_list_completion_path(@list)

    assert_redirected_to grocery_list_path(@list)
    assert_predicate @list.reload, :completed?
  end
  test "shopping again puts a finished list back, with nothing in the basket" do
    @list.finish!

    delete grocery_list_completion_path(@list)

    assert_redirected_to grocery_list_path(@list)
    assert_predicate @list.reload, :active?
    assert_not grocery_list_items(:eggs_item).reload.checked?
  end
  test "a housemate the list is shared with can finish it" do
    sign_in profiles(:bob)
    post grocery_list_completion_path(@list)

    assert_redirected_to grocery_list_path(@list)
    assert_predicate @list.reload, :completed?
  end
  test "someone the list isn't shared with can't finish or open it" do
    sign_in profiles(:carol)

    post grocery_list_completion_path(@list)
    assert_not @list.reload.completed?

    get grocery_list_path(@list)
    assert_not_equal 200, response.status
  end
end
