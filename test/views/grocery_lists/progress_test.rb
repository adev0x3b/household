# frozen_string_literal: true

require "test_helper"

class Views::GroceryLists::ProgressTest < ActiveSupport::TestCase
  test "a list being shopped says how much is bought, with a bar" do
    list = grocery_lists(:weekly_shop)
    progress = Views::GroceryLists::Progress.new(grocery_list: list)

    assert_equal I18n.t("grocery_lists.progress.bought", checked: list.checked_count, total: list.total_count), progress.text
    assert_equal 1, Nokogiri::HTML5.fragment(progress.call).css("[role=progressbar]").size
  end

  test "an empty list says so, and draws no bar" do
    progress = Views::GroceryLists::Progress.new(grocery_list: GroceryList.new(name: "Empty"))

    assert_equal I18n.t("grocery_lists.progress.empty"), progress.text
    assert_empty progress.call
  end
end
