# frozen_string_literal: true

require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "belongs to a profile and is one of the kinds" do
    event = events(:groceries)
    assert_equal profiles(:alice), event.profile
    assert_instance_of Task, event
    assert_equal Event.types.map(&:name), Event::TYPES
  end

  test "one person's reminders on it come soonest before first, nobody else's among them" do
    event = events(:groceries)
    event.event_reminders.create!(profile: profiles(:alice), offset_minutes: 2 * 24 * 60)
    event.event_reminders.create!(profile: profiles(:alice), offset_minutes: 60)
    event.event_reminders.create!(profile: profiles(:bob), offset_minutes: 30)

    assert_equal [ 60, 2 * 24 * 60 ], event.reminders_of(profiles(:alice)).map(&:offset_minutes)
  end

  test "requires a start date and a known kind" do
    event = Task.new(profile: profiles(:alice), title: "x")
    assert_not event.valid?
    assert_includes event.errors[:starts_on], "can't be blank"

    event = Event.new(profile: profiles(:alice), starts_on: Date.current)
    assert_not event.valid?
    assert_includes event.errors[:type], "is not included in the list"
  end

  test "each kind answers its section, fee category, statuses and details" do
    assert_equal :agenda, Task.section
    assert_equal :healthcare, Medication.section
    assert_equal :finance, Transaction.section
    assert_equal :pantry, Meal.section
    assert_nil Appointment.section, "an appointment decides by kind"
    assert_equal :dining_out, Meal.fee_category
    assert_equal %w[pending in_progress completed cancelled skipped], Task.allowed_statuses
    assert_equal Medication::Details, Medication.details_class
  end

  test "the series' details row is built on first touch and saved with the series" do
    task = Task.new(profile: profiles(:alice), starts_on: Date.current, title: "Vacuum")
    assert_predicate task.details, :new_record?
    assert_equal "low", task.details.priority
    task.save!
    assert_predicate task.details, :persisted?
    assert_nil task.details.occurrence_id
  end

  test "the times of the day set again as they are leave the series as it was; others replace them" do
    event = events(:water_the_plants)
    event.assign_slots([ "08:00", "CV" ])
    event.save!
    slots = event.reload.event_slots.map(&:id)
    stamp = event.updated_at

    travel(1.minute) do
      event.assign_slots([ "CV", "08:00" ])
      event.save!
    end
    assert_equal slots, event.reload.event_slots.map(&:id)
    assert_equal stamp, event.updated_at, "a form sends them with every save"

    travel(2.minutes) do
      event.assign_slots([ "09:00" ])
      event.save!
    end
    assert_equal [ [ "09:00", nil ] ], event.reload.slots
    assert_operator event.updated_at, :>, stamp
  end

  test "recurring? follows the rule, which must parse" do
    assert_not events(:groceries).recurring?
    assert_predicate events(:water_the_plants), :recurring?

    bad = Task.new(profile: profiles(:alice), starts_on: Date.current, title: "x", rrule: "FREQ=SOMETIMES")
    assert_not bad.valid?
    assert_predicate bad.errors[:rrule], :any?
  end

  test "the schedule starts on starts_on and follows the rule" do
    event = events(:water_the_plants)
    dates = event.occurrence_dates_between(Date.new(2026, 3, 1), Date.new(2026, 3, 31))
    assert_equal [ 2, 9, 16, 23, 30 ].map { |d| Date.new(2026, 3, d) }, dates

    event.rrule = "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO"
    assert_equal [ 2, 16, 30 ].map { |d| Date.new(2026, 3, d) }, event.occurrence_dates_between(Date.new(2026, 3, 1), Date.new(2026, 3, 31)), "a changed rule drops the memoized schedule"
  end

  test "occurrence_dates_between returns the single date of a one-off" do
    dates = events(:groceries).occurrence_dates_between(Date.new(2026, 3, 1), Date.new(2026, 3, 31))
    assert_equal [ Date.new(2026, 3, 2) ], dates
    assert_empty events(:groceries).occurrence_dates_between(Date.new(2026, 4, 1), Date.new(2026, 4, 30))
  end

  test "skip! removes a day from the series and unskip! puts it back" do
    event = events(:water_the_plants)
    day = Date.new(2026, 3, 16)

    event.skip!(day)
    assert event.excluded_on?(day)
    assert_not_includes event.occurrence_dates_between(Date.new(2026, 3, 1), Date.new(2026, 3, 31)), day

    event.unskip!(day)
    assert_not event.excluded_on?(day)
    assert_includes event.occurrence_dates_between(Date.new(2026, 3, 1), Date.new(2026, 3, 31)), day
  end

  test "occurrences_between yields the saved day where there is one, an unsaved Occurrence elsewhere" do
    event = events(:water_the_plants)
    saved = event.occurrence_on(Date.new(2026, 3, 9)).tap { |o| o.update!(status: :completed, completed_at: Time.current) }

    days = event.occurrences_between(Date.new(2026, 3, 1), Date.new(2026, 3, 16))
    assert_equal [ 2, 9, 16 ].map { |d| Date.new(2026, 3, d) }, days.map(&:date)
    assert_predicate days.first, :projected?
    assert_equal saved, days.second
    assert_predicate days.second, :completed?
    assert_equal event, days.first.event
    assert_equal "Water the plants", days.first.title, "a projected day reads the series"
  end

  test "a saved day moved off the schedule still shows" do
    event = events(:water_the_plants)
    moved = event.occurrences.create!(date: Date.new(2026, 3, 4))

    days = event.occurrences_between(Date.new(2026, 3, 1), Date.new(2026, 3, 10))
    assert_equal [ Date.new(2026, 3, 2), Date.new(2026, 3, 4), Date.new(2026, 3, 9) ], days.map(&:date)
    assert_includes days, moved
  end

  test "occurrence_on gives the saved day or a new one, and a saved one keeps its identity" do
    event = events(:groceries)
    assert_equal occurrences(:groceries_due), event.occurrence_on(Date.new(2026, 3, 2))

    fresh = event.occurrence_on(Date.new(2026, 3, 16))
    assert_predicate fresh, :new_record?
    assert_equal event, fresh.event
    assert_equal "Buy groceries", fresh.title
  end

  # A daily medication taken at `times`, for the tests of doses below.
  def daily(times: [], starts_on: Date.new(2026, 10, 5))
    series!("Medication", profile: profiles(:alice), starts_on: starts_on, title: "Metformin", rrule: "FREQ=DAILY", slots: times)
  end

  test "occurrences_between expands each day into its slots, anchors resolved to the household's hours" do
    event = daily(times: %w[CV 08:00])

    occurrences = event.occurrences_between(Date.new(2026, 10, 6), Date.new(2026, 10, 7))

    assert_equal([ [ Date.new(2026, 10, 6), "08:00", nil ], [ Date.new(2026, 10, 6), "19:30", "CV" ],
                   [ Date.new(2026, 10, 7), "08:00", nil ], [ Date.new(2026, 10, 7), "19:30", "CV" ] ],
                 occurrences.map { |o| [ o.date, o.time_string, o.anchor ] })
    assert_equal [ Date.new(2026, 10, 6), "08:00" ], event.occurrences_between(Date.new(2026, 10, 6), Date.new(2026, 10, 6)).first.key
    assert_equal [ [ "08:00", nil ], [ "19:30", "CV" ] ], event.reload.slots, "in clock order"
  end

  test "a series without slots is one untimed day" do
    event = daily

    occurrences = event.occurrences_between(Date.new(2026, 10, 6), Date.new(2026, 10, 6))

    assert_equal 1, occurrences.size
    assert_nil occurrences.first.time
    assert_not event.timed?
    assert_equal [ [ nil, nil ] ], event.slots
  end

  test "slots are cleaned up on the way in" do
    event = daily(times: [ " cv ", "08:00", "08:00", "bogus", "" ])
    assert_equal [ [ "08:00", nil ], [ "19:30", "CV" ] ], event.slots
    assert_not EventSlot.new(event: event, time: "09:00", position: 9, anchor: "XX").valid?
  end

  test "skipping one slot leaves the rest of the day, skipping the day removes every slot" do
    event = daily(times: %w[08:00 20:00])
    day = Date.new(2026, 10, 6)

    event.skip!(day, time: "20:00")
    assert_equal [ "08:00" ], event.occurrences_between(day, day).map(&:time_string)
    assert_not event.excluded_on?(day)
    assert_includes event.occurrence_dates_between(day, day), day

    event.unskip!(day, time: "20:00")
    assert_equal %w[08:00 20:00], event.occurrences_between(day, day).map(&:time_string)

    event.skip!(day)
    assert_empty event.occurrences_between(day, day)
    assert event.excluded_on?(day)
  end

  test "occurrence_on gives a dose its time and anchor, and the lookups tell doses apart" do
    event = daily(times: %w[CM CV])
    day = Date.new(2026, 10, 6)

    dose = event.occurrence_on(day, time: "19:30")
    assert_equal "Metformin", dose.title
    assert_equal "19:30", dose.time_string
    assert_equal "CV", dose.anchor, "the anchor of the slot it falls in"
    dose.save!

    assert_equal dose, event.occurrence_on(day, time: "19:30")
    assert_predicate event.occurrence_on(day, time: "08:00"), :new_record?
    assert_equal [ dose ], event.occurrences_between(day, day).select(&:persisted?)
  end

  test "occurrence_for picks the dose named, else the first still to take, else the last" do
    event = daily(times: %w[08:00 20:00])
    day = Date.new(2026, 10, 6)

    assert_equal "08:00", event.occurrence_for(day).time_string
    assert_equal "20:00", event.occurrence_for(day, time: "20:00").time_string

    morning = event.occurrence_for(day)
    morning.complete!
    assert_equal "20:00", event.occurrence_for(day).time_string, "the morning one is taken"

    evening = event.occurrence_for(day)
    evening.complete!
    assert_equal evening, event.occurrence_for(day), "all taken: the last one"
    assert_equal morning, event.occurrence_for(day, time: "08:00")

    extra = event.occurrence_for(day, time: "14:00")
    assert_predicate extra, :new_record?
    assert_equal "14:00", extra.time_string
    assert_nil extra.anchor
  end

  test "preloading the saved days of a month needs no query per series" do
    events = [ events(:water_the_plants), events(:groceries) ]
    saved = occurrences(:groceries_due)
    Event.preload_occurrences(events, Date.new(2026, 3, 1), Date.new(2026, 3, 31))

    assert_no_queries do
      assert_equal 5, events.first.occurrences_between(Date.new(2026, 3, 1), Date.new(2026, 3, 31)).size
      assert_equal saved, events.second.occurrences_between(Date.new(2026, 3, 1), Date.new(2026, 3, 31)).first
    end
  end

  test "a series reloaded reads its days again, not the ones preloaded before" do
    event = events(:water_the_plants)
    Event.preload_occurrences([ event ], Date.new(2026, 3, 1), Date.new(2026, 3, 31))
    Event.find(event.id).occurrence_on(Date.new(2026, 3, 16)).update!(notes: "Only the basil")

    day = event.reload.occurrence_on(Date.new(2026, 3, 16))
    assert_predicate day, :persisted?
    assert_equal "Only the basil", day.notes
  end

  test "preloading a range reads every day's details, its own or the series', and what they plan to use, without a query" do
    event = daily(times: %w[08:00])
    supply = Supply.create!(profile: profiles(:alice), name: "Strips", unit_label: "strip")
    event.details.replace_uses!([ [ supply.id, "1" ] ])
    event.occurrence_on(Date.new(2026, 10, 6), time: "08:00").write_details!(quantity: 2)
    event = Event.find(event.id)

    Event.preload_occurrences([ event ], Date.new(2026, 10, 5), Date.new(2026, 10, 7))

    assert_no_queries do
      days = event.occurrences_between(Date.new(2026, 10, 5), Date.new(2026, 10, 7))
      assert_equal([ nil, BigDecimal("2"), nil ], days.map { |day| day.details.quantity })
      assert_equal([ [ "Strips" ] ] * 3, days.map { |day| day.details.resolved_uses.map { |use| use.supply.name } })
    end
  end

  test "the series nothing was ever saved about are those without a single day's row" do
    untouched = daily
    saved = daily
    saved.occurrence_on(Date.new(2026, 10, 6)).complete!

    assert_includes Event.without_saved_days, untouched
    assert_not_includes Event.without_saved_days, saved
  end

  # An anti-join reads each series' days through their index; NOT IN over
  # every household's days is never planned as one, however few rows.
  test "the series nothing was ever saved about are found by an anti-join" do
    plan = Event.connection.select_values("EXPLAIN #{Event.without_saved_days.to_sql}").join("\n")

    assert_match "Anti Join", plan
  end

  test "a series' continuation carries its body, collection, details and lists, and an injection keeps alternating" do
    strips = Supply.create!(profile: profiles(:alice), name: "Strips", unit_label: "strip")
    event = series!("Medication", profile: profiles(:alice), starts_on: Date.new(2026, 10, 5), title: "Insulin", rrule: "FREQ=DAILY",
                                  slots: %w[CM], collection: collections(:b12), kind: :injection, area: :thigh, side: :left, quantity: 2, unit: "ml")
    event.details.replace_uses!([ [ strips.id, "1" ] ])
    event.event_shares.create!(profile: profiles(:bob))

    copy = event.continuation(starts_on: Date.new(2026, 10, 8))
    copy.update!(rrule: "FREQ=DAILY")
    event.hand_over_audience_to!(copy)

    assert_equal [ "Insulin", collections(:b12), Date.new(2026, 10, 8) ], [ copy.title, copy.collection, copy.starts_on ]
    assert_equal event.slots, copy.reload.slots
    assert_equal [ "injection", "thigh", BigDecimal("2"), "ml" ], copy.details.values_at(:kind, :area, :quantity, :unit)
    assert_equal "right", copy.details.side, "the 4th dose of a daily series alternates to the other side"
    assert_equal([ [ strips.id, BigDecimal("1") ] ], copy.details.supply_uses.map { |use| [ use.supply_id, use.quantity ] })
    assert_equal [ profiles(:bob) ], copy.shared_profiles.to_a
    assert_equal [ [ strips.id, BigDecimal("1") ] ], event.details.reload.supply_uses.map { |use| [ use.supply_id, use.quantity ] }, "the old series keeps its own"
  end

  test "purging a series takes its days, its details and its slots with it" do
    event = daily(times: %w[08:00])
    dose = event.occurrence_on(Date.new(2026, 10, 6), time: "08:00").tap(&:materialize!)
    dose.write_details!(quantity: 2)

    Events::Purge.call([ event ])

    assert_not Event.exists?(event.id)
    assert_not Occurrence.exists?(dose.id)
    assert_empty Medication::Details.where(event_id: event.id)
    assert_empty EventSlot.where(event_id: event.id)
  end

  test "a series is removed through Events::Purge: destroy on one fails rather than half-remove it" do
    event = daily(times: %w[08:00])

    assert_raises(ActiveRecord::InvalidForeignKey) { event.destroy }
    assert Event.exists?(event.id)
  end
end
