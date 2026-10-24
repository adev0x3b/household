# frozen_string_literal: true

require "application_system_test_case"

# A grocery list as it is shopped: items typed one line at a time into the
# quick add (quick_add_controller.js clears it after each one, and keeps
# what was refused to be corrected), ticked into the basket, which puts
# them in the pantry, and the shop finished.
class GroceryListsTest < ApplicationSystemTestCase
  setup do
    @alice = profiles(:alice)
    @list = GroceryList.create!(profile: @alice, name: "Saturday market")
    sign_in @alice
  end

  test "items added with the quick add and ticked go into the pantry, and the shop is finished" do
    visit grocery_list_path(@list)

    quick_add "2 kg flour"
    assert_selector ".grocery-list-item-row", text: ingredients(:flour).name
    assert_field I18n.t("grocery_list_items.quick_add.label"), with: "", focused: true # ready for the next item
    quick_add "6 pcs eggs"
    assert_selector ".grocery-list-item-row", text: ingredients(:eggs).name

    quick_add "flour"
    assert_text I18n.t("grocery_list_items.notices.duplicate", name: ingredients(:flour).name)
    assert_field I18n.t("grocery_list_items.quick_add.label"), with: "flour" # left to be corrected
    fill_in I18n.t("grocery_list_items.quick_add.label"), with: ""
    assert_accessible "a list being shopped"

    click_on I18n.t("grocery_list_items.check", item: "#{ingredients(:flour).name} 2 kg")
    click_on I18n.t("grocery_list_items.check", item: "#{ingredients(:eggs).name} 6 pcs")
    within(".grocery-list-finish") do # shown the moment the last item is in the basket
      assert_text I18n.t("grocery_lists.show.all_bought")
      click_on I18n.t("grocery_lists.show.finish_cta")
    end

    assert_text I18n.t("grocery_lists.notices.finished")
    assert_text I18n.t("grocery_lists.status.completed")
    assert_no_field I18n.t("grocery_list_items.quick_add.label") # a finished list takes no more items
    assert_predicate @list.reload, :completed?

    visit ingredients_path
    within("#ingredient_#{ingredients(:flour).id}") { assert_text "4.5 kg" }
    within("#ingredient_#{ingredients(:eggs).id}") { assert_text "18 pcs" }
  end

  private

  def quick_add(line)
    fill_in I18n.t("grocery_list_items.quick_add.label"), with: line
    find_field(I18n.t("grocery_list_items.quick_add.label")).send_keys(:enter)
  end
end
