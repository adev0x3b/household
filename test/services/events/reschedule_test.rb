# frozen_string_literal: true

require "test_helper"

# A series with a past keeps it when its repeat or its times change: the
# days it had are what happened, and the new pattern goes on from today.
class Events::RescheduleTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 7, 12) # a Wednesday
    @alice = profiles(:alice)
    @today = Date.current
  end

  teardown { travel_back }

  def unfinished(event)
    Reports::Unfinished.new(Reports::Audience.new(viewer: @alice), today: @today).entries(of: event.class) { _1.id == event.id }
  end

  def reschedule(event, **)
    result = Events::Reschedule.call(event, **)
    assert_predicate result, :success?, result.error.to_s
    result.series
  end

  # Every Monday since August, done each week, the viewer reminded and Bob in on it.
  def bins
    series!("Task", profile: @alice, starts_on: Date.new(2026, 8, 3), title: "Bins", rrule: "FREQ=WEEKLY;BYDAY=MO").tap do |event|
      event.occurrences_between(event.starts_on, @today - 1).each(&:complete!)
      event.event_shares.create!(profile: profiles(:bob))
      event.event_reminders.create!(profile: @alice, offset_minutes: 60)
    end
  end

  test "moving a series to another weekday leaves its past alone, and the new series takes over its audience" do
    event = bins
    assert_empty unfinished(event)

    series = reschedule(event, rrule: "FREQ=WEEKLY;BYDAY=TU")

    assert_not_equal event, series
    assert_equal [ Date.new(2026, 10, 13), "Bins", "FREQ=WEEKLY;BYDAY=TU" ], [ series.starts_on, series.title, series.rrule ]
    assert_equal @today - 1, Events::RecurrenceRule.describe(event.reload.rrule)[:ends], "the old series ended yesterday"
    assert_empty unfinished(event), "no Tuesday is owed for the weeks that were Mondays"
    assert_equal 10, event.occurrences.completed.count, "the Mondays done stay done"
    assert_equal [ profiles(:bob) ], series.shared_profiles.to_a
    assert_equal [ 60 ], series.reminders_of(@alice).map(&:offset_minutes)
  end

  test "moving a dose to another time leaves its past alone" do
    event = series!("Medication", profile: @alice, starts_on: @today - 14, title: "Metformin", slots: %w[08:00], rrule: "FREQ=DAILY")
    event.occurrences_between(@today - 14, @today - 1).each(&:complete!)

    series = reschedule(event, rrule: event.rrule, slots: %w[09:00])

    assert_empty unfinished(event), "no 09:00 dose is owed for the days taken at 08:00"
    assert_equal [ @today, [ [ "09:00", nil ] ] ], [ series.starts_on, series.slots ]
    assert_equal [ [ "08:00", nil ] ], event.reload.slots
  end

  test "a dose taken today is on the record: the new times start tomorrow" do
    event = series!("Medication", profile: @alice, starts_on: @today - 3, title: "Metformin", slots: %w[08:00 20:00], rrule: "FREQ=DAILY")
    event.occurrence_on(@today, time: "08:00").complete!

    series = reschedule(event, rrule: event.rrule, slots: %w[09:00 21:00])

    assert_equal @today + 1, series.starts_on
    assert_equal @today, Events::RecurrenceRule.describe(event.reload.rrule)[:ends]
    assert_equal [ [ @today, "08:00" ], [ @today, "20:00" ] ], event.occurrences_between(@today, @today).map(&:key), "today goes on as planned"
  end

  test "a series going on under a new rule keeps its footing: the fortnight, the day of the month" do
    fortnightly = series!("Task", profile: @alice, starts_on: Date.new(2026, 9, 7), title: "Recycling", rrule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO")
    assert_equal Date.new(2026, 10, 20), reschedule(fortnightly, rrule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=TU").starts_on, "the Tuesday of the fortnight of 19 October"

    monthly = series!("Transaction", profile: @alice, starts_on: Date.new(2026, 1, 20), title: "Rent", rrule: "FREQ=MONTHLY",
                                     kind: :expense, category: :housing, amount_cents: 80_000, currency: "EUR", payment_method: :bank_transfer)
    assert_equal Date.new(2026, 11, 20), reschedule(monthly, rrule: "FREQ=MONTHLY;INTERVAL=2").starts_on, "the odd months from January"
  end

  test "a series whose days are all ahead, or whose pattern stays, takes the change in place" do
    ahead = series!("Task", profile: @alice, starts_on: @today + 1, title: "Bins", rrule: "FREQ=WEEKLY;BYDAY=TH")
    assert_equal ahead, reschedule(ahead, rrule: "FREQ=WEEKLY;BYDAY=FR")
    assert_equal "FREQ=WEEKLY;BYDAY=FR", ahead.reload.rrule

    event = bins
    ended = Events::RecurrenceRule.build(frequency: "weekly", week_days: %w[monday], ends: @today + 30)
    assert_no_difference "Event.count" do
      assert_equal event, reschedule(event, rrule: ended, slots: [])
    end
    assert_equal @today + 30, Events::RecurrenceRule.describe(event.reload.rrule)[:ends]

    one_off = series!("Medication", profile: @alice, starts_on: @today - 1, title: "Vaccine", slots: %w[10:00])
    assert_equal one_off, reschedule(one_off, rrule: nil, slots: %w[11:00])
    assert_equal [ [ "11:00", nil ] ], one_off.reload.slots
  end

  test "taking the repeat away from a series with a past stops it, its missed days kept" do
    event = series!("Task", profile: @alice, starts_on: Date.new(2026, 9, 28), title: "Water the ferns", rrule: "FREQ=DAILY")

    assert_no_difference "Event.count" do
      assert_equal event, reschedule(event, rrule: nil)
    end
    assert_equal @today - 1, Events::RecurrenceRule.describe(event.reload.rrule)[:ends]
    assert_equal 9, unfinished(event).size
  end

  test "a new rule with no day to come changes nothing and says so" do
    event = bins
    result = Events::Reschedule.call(event, rrule: Events::RecurrenceRule.build(frequency: "weekly", week_days: %w[tuesday], ends: @today))

    assert_equal :never_happens, result.error
    assert_equal "FREQ=WEEKLY;BYDAY=MO", event.reload.rrule
  end
end
