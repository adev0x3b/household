# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class GroceryListsControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    @profile = profiles(:alice)
    @list = grocery_lists(:weekly_shop) # flour to buy, eggs in the basket; shared with profile two
    sign_in @profile
  end

  test "index puts the lists being shopped first and folds the finished ones away" do
    done = GroceryList.create!(profile: @profile, name: "Last Saturday", status: :completed)

    get grocery_lists_path

    assert_response :success
    assert_select "#grocery_lists_list #grocery_list_#{@list.id}"
    assert_select "#grocery_lists_list #grocery_list_#{done.id}", count: 0
    assert_select "details#grocery_lists_completed #grocery_list_#{done.id}"
    assert_select "details#grocery_lists_completed[open]", count: 0
    assert_select "#grocery_list_#{@list.id}", text: /1 of 2 bought/
    assert_select "#grocery_list_#{done.id} .item-menu a[href=?]", grocery_list_completion_path(done)
  end

  test "index without finished lists has no folded section" do
    get grocery_lists_path
    assert_select "details#grocery_lists_completed", count: 0
  end

  test "show groups what is to buy by store section, folds the basket away and offers the quick-add" do
    ingredients(:flour).update!(category: :pantry)

    get grocery_list_path(@list)

    assert_response :success
    assert_select "turbo-cable-stream-source"
    assert_select "form.grocery-list-quick-add input[name=?]", "grocery_list_item[text]"
    assert_select ".grocery-list-group__title", text: /Dry goods/
    assert_select ".grocery-list-group #grocery_list_item_#{grocery_list_items(:flour_item).id}"
    assert_select ".disclosure #grocery_list_item_#{grocery_list_items(:eggs_item).id}.grocery-list-item-row--checked"
    assert_select ".disclosure__title", text: "In the basket (1)"
    assert_select ".grocery-list-show__progress", text: "1 of 2 bought"
    assert_select ".grocery-list-finish", count: 0
  end

  test "show offers to finish once everything is in the basket" do
    grocery_list_items(:flour_item).check!

    get grocery_list_path(@list)

    assert_select ".grocery-list-finish form[action=?]", grocery_list_completion_path(@list)
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?][data-turbo-method=post]", grocery_list_completion_path(@list)
  end

  test "a finished list has no quick-add and can be shopped again from the navbar" do
    @list.finish!

    get grocery_list_path(@list)

    assert_select "form.grocery-list-quick-add", count: 0
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?][data-turbo-method=delete]", grocery_list_completion_path(@list)
    assert_select ".navbar-topbar-controls a[href=?][data-turbo-method=post]", grocery_list_completion_path(@list), count: 0
  end

  test "the owner's navbar has finish and share, then rename and delete behind more; a housemate's has no share or delete" do
    get grocery_list_path(@list)
    assert_select ".navbar-topbar-controls a.page-controls__action[href=?]", new_grocery_list_share_path(grocery_list_id: @list.id)
    assert_select ".navbar-topbar-controls .item-menu a.item-menu__entry[href=?]", edit_grocery_list_path(@list)
    assert_select ".navbar-topbar-controls a.item-menu__entry--danger[data-turbo-method=delete][href=?]", grocery_list_path(@list)

    sign_in profiles(:bob)
    get grocery_list_path(@list)
    assert_response :success
    assert_select ".navbar-topbar-controls a[href=?]", new_grocery_list_share_path(grocery_list_id: @list.id), count: 0
    assert_select ".navbar-topbar-controls a[data-turbo-method=delete][href=?]", grocery_list_path(@list), count: 0
    assert_select ".grocery-list-show__shared", text: /list/
  end

  test "create comes back to the index with the new list on it" do
    get new_grocery_list_path, as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals] form[action=?] input[name='grocery_list[name]']", grocery_lists_path

    assert_difference -> { @profile.grocery_lists.count }, 1 do
      post grocery_lists_path, params: { grocery_list: { name: "Barbecue" } }, headers: submitted_from(grocery_lists_path)
    end

    assert_redirected_to grocery_lists_path
    follow_redirect!
    assert_select ".grocery-list-card__name", text: "Barbecue"
  end

  test "renaming from the list page comes back to it, under its new name" do
    patch grocery_list_path(@list), params: { grocery_list: { name: "Big shop" } }, headers: submitted_from(grocery_list_path(@list))

    assert_redirected_to grocery_list_path(@list)
    assert_equal "Big shop", @list.reload.name
    follow_redirect!
    assert_select "title", text: /Big shop/
  end

  test "the form changes only the name; finishing and reopening happen on the list" do
    @list.finish!

    patch grocery_list_path(@list), params: { grocery_list: { name: "Big shop", status: "active" } }, headers: submitted_from(grocery_list_path(@list))

    assert_redirected_to grocery_list_path(@list)
    assert_equal "Big shop", @list.reload.name
    assert_predicate @list, :completed?
  end

  test "only the owner deletes: from the list's page they land on the index, from the index they stay on it as it was" do
    sign_in profiles(:bob)
    delete grocery_list_path(@list)
    assert GroceryList.exists?(@list.id)

    sign_in @profile
    gone = capture_turbo_stream_broadcasts([ profiles(:bob), :notifications ]) do
      delete grocery_list_path(@list), headers: submitted_from(grocery_list_path(@list))
    end
    assert_redirected_to grocery_lists_path
    assert_not GroceryList.exists?(@list.id)
    assert_equal [ "remove", "grocery_list_#{@list.id}" ], [ gone.sole["action"], gone.sole["target"] ], "it leaves the housemate's lists page"

    barbecue = @profile.grocery_lists.create!(name: "Barbecue")
    searched = grocery_lists_path(q: "barb")
    delete grocery_list_path(barbecue), headers: submitted_from(searched)
    assert_redirected_to searched
  end
end
