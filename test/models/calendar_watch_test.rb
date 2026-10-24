# frozen_string_literal: true

require "test_helper"

# The calendar months someone has open, known to every process: a row per
# open page, refreshed while it stays open.
class CalendarWatchTest < ActiveSupport::TestCase
  setup { @alice = profiles(:alice) }

  def room(month) = "profile_#{@alice.id}:#{month}"

  test "a month is open while any page on it is; each page counts on its own" do
    CalendarWatch.watch!(room("2026-10"), "tab-1")
    CalendarWatch.watch!(room("2026-10"), "tab-2")
    CalendarWatch.watch!(room("2026-11"), "tab-3")
    assert_equal %w[2026-10 2026-11], CalendarWatch.months_for(@alice.id).sort

    CalendarWatch.unwatch!("tab-1")
    assert_equal %w[2026-10 2026-11], CalendarWatch.months_for(@alice.id).sort, "tab-2 is still on October"
    CalendarWatch.unwatch!("tab-2")
    assert_equal %w[2026-11], CalendarWatch.months_for(@alice.id)
  end

  test "a page nothing refreshes stops counting, and is swept away later" do
    CalendarWatch.watch!(room("2026-10"), "tab-1")

    travel(CalendarWatch::STALE_AFTER + 1.second) do
      assert_empty CalendarWatch.months_for(@alice.id)
      CalendarWatch.watch!(room("2026-10"), "tab-1") # the channel's refresh
      assert_equal %w[2026-10], CalendarWatch.months_for(@alice.id)
    end

    travel(2.hours) { CalendarWatch.sweep! }
    assert_empty CalendarWatch.all
  end

  test "a room that isn't one is ignored" do
    assert_no_difference("CalendarWatch.count") { CalendarWatch.watch!("profile_1:2026-13x", "tab-1") }
  end
end
