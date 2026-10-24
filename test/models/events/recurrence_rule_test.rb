# frozen_string_literal: true

require "test_helper"

class Events::RecurrenceRuleTest < ActiveSupport::TestCase
  test "builds an RRULE line from the plain fields and reads it back" do
    line = Events::RecurrenceRule.build(frequency: "weekly", interval: 2, week_days: %w[monday Friday bogus])
    assert_equal "FREQ=WEEKLY;INTERVAL=2;WKST=SU;BYDAY=MO,FR", line
    assert_equal({ frequency: "weekly", interval: 2, week_days: %w[monday friday] }, Events::RecurrenceRule.describe(line))

    assert_equal({ frequency: "daily", interval: 1, week_days: [] }, Events::RecurrenceRule.describe(Events::RecurrenceRule.build(frequency: "daily")))
    assert_equal "monthly", Events::RecurrenceRule.describe(Events::RecurrenceRule.build(frequency: "monthly"))[:frequency]
    assert_equal "yearly", Events::RecurrenceRule.describe(Events::RecurrenceRule.build(frequency: "yearly"))[:frequency]
  end

  test "an end date survives the round trip" do
    line = Events::RecurrenceRule.build(frequency: "daily", ends: "2026-12-31")
    assert_match(/UNTIL=/, line)
    assert_equal Date.new(2026, 12, 31), Events::RecurrenceRule.describe(line)[:ends]
  end

  test "a line's pattern is how it repeats, whenever it ends" do
    weekly = Events::RecurrenceRule.build(frequency: "weekly", week_days: %w[monday])
    ended = Events::RecurrenceRule.build(frequency: "weekly", week_days: %w[monday], ends: "2026-12-31")

    assert_equal Events::RecurrenceRule.pattern(weekly), Events::RecurrenceRule.pattern(ended)
    assert_not_equal Events::RecurrenceRule.pattern(weekly), Events::RecurrenceRule.pattern("FREQ=WEEKLY;BYDAY=TU")
    assert_equal({ frequency: "none" }, Events::RecurrenceRule.pattern(nil))
  end

  test "a line read as a form's fields has every field filled in" do
    weekly = Events::RecurrenceRule.fields("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR")
    one_off = Events::RecurrenceRule.fields(nil)

    assert_equal [ "weekly", 2, %w[monday friday], nil ], weekly.deconstruct
    assert_predicate weekly, :repeats?
    assert_equal [ "none", 1, [], nil ], one_off.deconstruct
    assert_not_predicate one_off, :repeats?
    assert_equal Date.new(2026, 12, 31), Events::RecurrenceRule.fields(Events::RecurrenceRule.build(frequency: "daily", ends: "2026-12-31")).ends
  end

  test "a line that can't be read is reported and read as a one-off" do
    broken = nil
    assert_error_reported(ArgumentError) { broken = Events::RecurrenceRule.fields("FREQ=SOMETIMES") }

    assert_equal Events::RecurrenceRule::Fields.one_off, broken
  end

  test "no frequency is no rule" do
    assert_nil Events::RecurrenceRule.build(frequency: "none")
    assert_nil Events::RecurrenceRule.build(frequency: "")
    assert_equal({ frequency: "none" }, Events::RecurrenceRule.describe(nil))
    assert_raises(ArgumentError) { Events::RecurrenceRule.parse("") }
  end

  test "a series' dates are its start date walked by the line, minus the days deleted from it" do
    event = Task.new(profile: profiles(:alice), starts_on: Date.new(2026, 3, 2), title: "x", rrule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH")
    event.event_exclusions.build(date: Date.new(2026, 3, 16))

    assert_equal [ Date.new(2026, 3, 2), Date.new(2026, 3, 5), Date.new(2026, 3, 19), Date.new(2026, 3, 30), Date.new(2026, 4, 2) ],
                 event.occurrence_dates_between(Date.new(2026, 3, 1), Date.new(2026, 4, 5))
  end
end
