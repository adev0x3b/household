# frozen_string_literal: true

require "test_helper"

# A domain's badge only picks a look and a word for each of its values;
# these hold that every value has both, so a new status or priority can't
# render as a bare colour.
class Views::StatusBadgesTest < ActiveSupport::TestCase
  test "every priority of a task has a look and its word" do
    assert_equal Task::Details.priorities.keys.sort, Views::Tasks::PriorityBadge::LOOKS.keys.sort

    Task::Details.priorities.each_key do |priority|
      badge = parse(Views::Tasks::PriorityBadge.new(priority: priority))
      assert_equal I18n.t("tasks.priority.#{priority}"), badge.at_css(".status-badge > span").text
    end
    assert parse(Views::Tasks::PriorityBadge.new(priority: "urgent")).at_css(".status-badge--critical i.fa-flag")
  end

  test "every status of a collection has a look and its word" do
    assert_equal Collection.statuses.keys.sort, Views::Collections::StatusBadge::LOOKS.keys.sort

    badge = parse(Views::Collections::StatusBadge.new(status: "paused"))
    assert badge.at_css(".status-badge--warning i.fa-pause")
    assert_equal I18n.t("collections.status.paused"), badge.at_css(".status-badge > span").text
  end

  test "every flag of a lab value has a look and its word" do
    flags = %i[normal low high abnormal]
    assert_equal flags.sort, Views::LabTestResults::FlagBadge::LOOKS.keys.sort

    flags.each do |flag|
      badge = parse(Views::LabTestResults::FlagBadge.new(flag: flag))
      assert_equal I18n.t("lab_test_results.form.entries.flags.#{flag}"), badge.at_css(".status-badge > span").text
    end
    assert parse(Views::LabTestResults::FlagBadge.new(flag: :abnormal)).at_css(".status-badge--critical")
  end

  test "every status of a grocery list has a look and its word" do
    assert_equal GroceryList.statuses.keys.sort, Views::GroceryLists::StatusBadge::LOOKS.keys.sort

    assert parse(Views::GroceryLists::StatusBadge.new(status: "active")).at_css(".status-badge--neutral i.fa-cart-shopping")
    badge = parse(Views::GroceryLists::StatusBadge.new(status: "completed"))
    assert badge.at_css(".status-badge--good")
    assert_equal I18n.t("grocery_lists.status.completed"), badge.at_css(".status-badge > span").text
  end

  test "every status of a book has a look and its word" do
    assert_equal Book.statuses.keys.sort, Views::Books::StatusBadge::LOOKS.keys.sort

    badge = parse(Views::Books::StatusBadge.new(status: "dropped"))
    assert badge.at_css(".status-badge--warning i.fa-ban")
    assert_equal I18n.t("books.status.dropped"), badge.at_css(".status-badge > span").text
  end

  test "every answer to an approval has a look" do
    assert_equal LinkApproval.statuses.keys.sort, Views::Links::ApprovalRow::LOOKS.keys.sort
  end

  private

  def parse(view) = Nokogiri::HTML5.fragment(view.call)
end
