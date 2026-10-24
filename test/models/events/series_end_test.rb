# frozen_string_literal: true

require "test_helper"

class Events::SeriesEndTest < ActiveSupport::TestCase
  FIRST = Date.new(2026, 11, 1) # a Sunday
  DAILY = "FREQ=DAILY"

  test "a course of fifteen days every day ends on the fifteenth, its first day counted" do
    ends = Events::SeriesEnd.from(ends_by: "after_count", ends_after: "15")

    assert_nil ends.error(starts_on: FIRST)
    assert_equal Date.new(2026, 11, 15), ends.last_day(starts_on: FIRST, rrule: DAILY)
    assert_equal Date.new(2026, 11, 29), ends.last_day(starts_on: FIRST, rrule: "FREQ=DAILY;INTERVAL=2"), "every other day, the fifteenth time"
  end

  test "a number of times counts the days the series falls on" do
    ends = Events::SeriesEnd.from(ends_by: "after_count", ends_after: "3")

    assert_equal Date.new(2026, 11, 3), ends.last_day(starts_on: FIRST, rrule: DAILY)
    assert_equal Date.new(2026, 11, 9), ends.last_day(starts_on: FIRST, rrule: "FREQ=WEEKLY;BYDAY=MO,FR"), "Monday 2, Friday 6, Monday 9"
    assert_equal Date.new(2026, 11, 1), Events::SeriesEnd.from(ends_by: "after_count", ends_after: "1").last_day(starts_on: FIRST, rrule: DAILY)
  end

  test "a day is the last day itself, and can't come before the first" do
    ends = Events::SeriesEnd.from(ends_by: "on_date", ends: "2026-11-20")

    assert_equal Date.new(2026, 11, 20), ends.last_day(starts_on: FIRST, rrule: DAILY)
    assert_nil ends.error(starts_on: FIRST)
    assert_nil ends.error(starts_on: Date.new(2026, 11, 20)), "a series may end on its first day"
    assert_equal :before_start, ends.error(starts_on: Date.new(2026, 11, 21))
    assert_equal :day_missing, Events::SeriesEnd.from(ends_by: "on_date", ends: "").error(starts_on: FIRST)
    assert_equal :day_missing, Events::SeriesEnd.from(ends_by: "on_date", ends: "soon").error(starts_on: FIRST)
  end

  test "a count is a whole number from one to the most" do
    %w[0 -3 1.5 ten].push("", (Events::SeriesEnd::MOST + 1).to_s).each do |count|
      assert_equal :count_out_of_range, Events::SeriesEnd.from(ends_by: "after_count", ends_after: count).error(starts_on: FIRST), count
    end
    assert_nil Events::SeriesEnd.from(ends_by: "after_count", ends_after: Events::SeriesEnd::MOST.to_s).error(starts_on: FIRST)
  end

  test "never has no last day, and a form that only sends the day it ends is read as that day" do
    assert_nil Events::SeriesEnd.from(ends_by: "never", ends: "2026-11-20").last_day(starts_on: FIRST, rrule: DAILY)
    assert_nil Events::SeriesEnd.from({}).last_day(starts_on: FIRST, rrule: DAILY)
    assert_equal Date.new(2026, 11, 20), Events::SeriesEnd.from(ends: "2026-11-20").last_day(starts_on: FIRST, rrule: DAILY)
    assert_instance_of Events::SeriesEnd::Never, Events::SeriesEnd.from(ends_by: "someday")
  end
end
