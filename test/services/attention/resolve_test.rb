# frozen_string_literal: true

require "test_helper"

# Settling "Needs attention" from its list: a series' days that passed
# unrecorded are marked skipped, each with its own policy's leave.
class Attention::ResolveTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @today = Date.current
  end

  test "every day of the series still to do is skipped, saved or not, and done days are left as they were" do
    series = weekly_event(profile: @alice, type: Medication, starts_on: @today - 21)
    taken = medication!(profile: @alice, date: @today - 21, status: :completed, event: series)
    open = medication!(profile: @alice, date: @today - 14, event: series)

    skipped = Attention::Resolve.call(series, by: @alice, today: @today)

    assert_equal [ @today - 14, @today - 7 ], skipped.map(&:date)
    assert skipped.all?(&:persisted?), "a day nothing was saved about is saved as skipped"
    assert_equal "skipped", open.reload.status
    assert_equal @alice, open.updated_by, "whoever settled the list is named on what it changed"
    assert_equal "completed", taken.reload.status
    assert_predicate series.occurrence_on(@today), :projected?, "today is not over yet"
  end

  test "many series at once, of several kinds" do
    task = task!(profile: @alice, date: @today - 1)
    meal = meal_on(@alice, @today - 2, title: "Lasagna")

    skipped = Attention::Resolve.call([ task.event, meal.event ], by: @alice, today: @today)

    assert_equal %w[skipped skipped], skipped.map(&:status)
    assert_equal "skipped", task.reload.status
    assert_equal "skipped", meal.reload.status
  end

  test "a linked housemate settles what the owner lets them change outright, and nothing they may only ask about" do
    link!(@alice, @bob)
    grant(@alice, @bob, "Task", write: :on)
    grant(@alice, @bob, "Meal", write: :ask)
    task = task!(profile: @alice, date: @today - 1)
    meal = meal_on(@alice, @today - 2, title: "Lasagna")

    skipped = Attention::Resolve.call([ task.event, meal.event ], by: @bob, today: @today)

    assert_equal [ task ], skipped
    assert_equal "skipped", task.reload.status
    assert_equal "pending", meal.reload.status
    assert_empty LinkApproval.where(requester: @bob), "nothing is asked of the owner"
  end

  test "someone the series is not shared with changes nothing" do
    task = task!(profile: @alice, date: @today - 1)

    assert_empty Attention::Resolve.call(task.event, by: profiles(:carol), today: @today)
    assert_equal "pending", task.reload.status
  end

  test "one series' cards are redrawn on the calendars that show them; many series refresh those calendars" do
    travel_to Time.utc(2026, 10, 15, 12)
    room = "profile_#{@alice.id}:2026-10"
    CalendarWatch.watch!(room, "alice's tab")
    bins = task!(profile: @alice, date: Date.new(2026, 10, 13), title: "Bins")

    one = capture_broadcasts(room) { Attention::Resolve.call(bins.event, by: @alice) }
    assert_equal 1, one.size
    assert_includes one.first, %(target="day_2026-10-13")

    plants = task!(profile: @alice, date: Date.new(2026, 10, 12), title: "Plants")
    lasagna = meal_on(@alice, Date.new(2026, 10, 11), title: "Lasagna")
    many = capture_broadcasts(room) { Attention::Resolve.call([ plants.event, lasagna.event ], by: @alice) }
    assert_equal 1, many.size
    assert_includes many.first, %(action="refresh")
  end
end
