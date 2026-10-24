# frozen_string_literal: true

require "test_helper"

class TaskTest < ActiveSupport::TestCase
  test "requires a title" do
    task = Task.new(profile: profiles(:alice), starts_on: Date.current)
    assert_not task.valid?
    assert_includes task.errors[:title], "can't be blank"
  end

  test "its priority lives on its details, low unless said" do
    task = Task.create!(profile: profiles(:alice), starts_on: Date.current, title: "Vacuum")
    assert_equal "low", task.details.priority
    assert_equal Task::Details.priorities["low"], task.priority_rank

    urgent = Task.create!(profile: profiles(:alice), starts_on: Date.current, title: "Call", details_attributes: { priority: :urgent })
    assert_equal Task::Details.priorities["urgent"], urgent.priority_rank
    assert_equal urgent.priority_rank, urgent.occurrence_on(Date.current).priority_rank
  end

  test "a task may be in progress" do
    day = occurrences(:groceries_due)
    day.change_status!("in_progress")
    assert_predicate day.reload, :in_progress?
  end

  test "a series and its days are named by its title" do
    assert_equal "Buy groceries", events(:groceries).event_label
    assert_equal "Buy groceries", occurrences(:groceries_due).event_label
  end

  # The numbers are what the database stores: changing one changes what
  # every saved row means.
  test "priorities and statuses keep their stored numbers" do
    assert_equal({ "low" => 0, "medium" => 1, "high" => 2, "urgent" => 3 }, Task::Details.priorities)
    assert_equal({ "pending" => 0, "in_progress" => 1, "completed" => 2, "cancelled" => 3, "skipped" => 4 }, Occurrence.statuses)
  end
end
