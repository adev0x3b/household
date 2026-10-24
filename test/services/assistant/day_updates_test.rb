# frozen_string_literal: true

require "test_helper"

# What the assistant's update does to one day of a series, and how undo
# brings it back: a dose's time said in words, a day moved off its slot
# (which the series then skips), a day moved into the past (done), the
# series' repeat changed with it.
class Assistant::DayUpdatesTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 7, 12) # a Wednesday
    @alice = profiles(:alice)
    @bins = weekly_event(profile: @alice, type: "Task", starts_on: Date.new(2026, 10, 5), title: "Bins") # Mondays
  end

  teardown { travel_back }

  def change!(*operations)
    data = Assistant::ChangeSets::Submit.call(chat: assistant_chat(@alice), operations: operations, confirm: true)
    assert_equal "saved", data[:status].to_s, data.inspect
    Assistant::ChangeSet.find(data[:change_set_id])
  end

  def undo(set) = Assistant::ChangeSets::Undoer.call(set.reload)

  test "a dose's time said in words is its clock time, or its meal" do
    twice = timed_medication!(profile: @alice, starts_on: Date.new(2026, 10, 1), times: %w[08:00 20:00]).event
    dose = twice.occurrences.find_by!(date: Date.new(2026, 10, 1))
    change!({ op: "update", type: "medication", ref: dose.id, fields: { time: "9pm" } })
    assert_equal [ "21:00", nil ], [ dose.reload.time_string, dose.anchor ]

    change!({ op: "update", type: "medication", ref: dose.id, fields: { time: "dinner" } })
    assert_equal "CV", dose.reload.anchor

    breakfast = Events::TimesOfDay.code_for("breakfast")
    change!({ op: "update", type: "medication", ref: dose.id, fields: { anchor: "breakfast" } })
    assert_equal [ breakfast, Events::TimesOfDay.hhmm(breakfast) ], [ dose.reload.anchor, dose.time_string ], "the meal's usual time with it"
  end

  test "a dose's change with new times of the day gives its series those times" do
    twice = timed_medication!(profile: @alice, starts_on: Date.new(2026, 10, 8), times: %w[08:00 20:00]).event
    dose = twice.occurrences.sole
    change!({ op: "update", type: "medication", ref: dose.id, fields: { quantity: 2, recurrence: { slots: %w[09:00 21:00] } } })

    assert_equal 2, dose.reload.details.quantity
    assert_equal %w[09:00 21:00], twice.reload.event_slots.map(&:time_string)
  end

  test "a day moved off its slot leaves the slot skipped, and undo puts both back" do
    monday = day!(@bins, date: Date.new(2026, 10, 12))
    moved = change!({ op: "update", type: "task", ref: monday.id, fields: { date: "2026-10-13" } })
    assert_equal Date.new(2026, 10, 13), monday.reload.date
    assert @bins.event_exclusions.exists?(date: Date.new(2026, 10, 12)), "the series doesn't project the Monday again"

    undo(moved)
    assert_equal Date.new(2026, 10, 12), monday.reload.date
    assert_not @bins.event_exclusions.reload.exists?(date: Date.new(2026, 10, 12))
  end

  test "a day moved twice leaves only its own slot skipped" do
    monday = day!(@bins, date: Date.new(2026, 10, 12))
    change!({ op: "update", type: "task", ref: monday.id, fields: { date: "2026-10-13" } })
    change!({ op: "update", type: "task", ref: monday.id, fields: { date: "2026-10-14" } })

    assert_equal Date.new(2026, 10, 14), monday.reload.date
    assert_equal [ Date.new(2026, 10, 12) ], @bins.event_exclusions.reload.map(&:date), "Tuesday was never one of the series' days"
  end

  test "a day's own priority changed twice stays the day's alone" do
    monday = day!(@bins, date: Date.new(2026, 10, 12))
    series_priority = @bins.details.priority
    change!({ op: "update", type: "task", ref: monday.id, fields: { priority: "high" } })
    change!({ op: "update", type: "task", ref: monday.id, fields: { priority: "medium" } })

    assert_equal "medium", monday.reload.details.priority
    assert_equal series_priority, @bins.reload.details.priority, "the other Mondays keep the series' priority"
  end

  test "a dose moved back to its time and away again skips that time once" do
    daily = timed_medication!(profile: @alice, starts_on: Date.new(2026, 10, 8), times: %w[08:00]).event
    dose = daily.occurrences.sole
    %w[09:00 08:00 10:00].each { |time| change!({ op: "update", type: "medication", ref: dose.id, fields: { time: time } }) }

    assert_equal "10:00", dose.reload.time_string
    skipped = daily.event_exclusions.reload.select { |exclusion| exclusion.date == dose.date && exclusion.time_string == "08:00" }
    assert_equal 1, skipped.size
  end

  test "a day moved into the past was done then; undo reopens it" do
    monday = day!(@bins, date: Date.new(2026, 10, 12))
    moved = change!({ op: "update", type: "task", ref: monday.id, fields: { date: "2026-10-06" } })
    assert_predicate monday.reload, :completed?

    undo(moved)
    assert_predicate monday.reload, :pending?
    assert_equal Date.new(2026, 10, 12), monday.date
  end

  test "a day's change with the series' repeat goes back together" do
    monday = day!(@bins, date: Date.new(2026, 10, 12))
    set = change!({ op: "update", type: "task", ref: monday.id, fields: { notes: "both bins", recurrence: { frequency: "daily" } } })
    assert_equal "both bins", monday.reload.notes
    daily = Task.find_by!(profile: @alice, title: "Bins", starts_on: Date.new(2026, 10, 7))
    assert_match "DAILY", daily.rrule
    assert_equal Date.new(2026, 10, 6), Events::RecurrenceRule.describe(@bins.reload.rrule)[:ends], "the Mondays ended yesterday"

    undo(set)
    assert_nil monday.reload.own_notes
    assert_not Event.exists?(daily.id)
    assert_equal "FREQ=WEEKLY", @bins.reload.rrule
  end

  test "a meal out takes its price as a payment named after it; a new amount keeps how it was paid" do
    pizza = meal_on(@alice, Date.new(2026, 10, 6), title: "Pizza with Sam", kind: :eating_out)
    change!({ op: "update", type: "meal", ref: pizza.id, fields: { amount: "24", payment_method: "card" } })
    cost = pizza.reload.costs.sole
    assert_equal [ BigDecimal("24"), "card", "Pizza with Sam" ], [ cost.details.amount, cost.details.payment_method, cost.details.counterparty ]

    change!({ op: "update", type: "meal", ref: pizza.id, fields: { amount: "30" } })
    assert_equal([ BigDecimal("30"), "card" ], pizza.reload.costs.sole.details.then { [ _1.amount, _1.payment_method ] })
  end

  test "a one-off dose taken, then its supplies changed: its own list and its stock follow, and come back on undo" do
    needles = supply_purchase!(profile: @alice, name: "Needles", quantity: 10).supply
    swabs = supply_purchase!(profile: @alice, name: "Swabs", quantity: 10).supply
    shot = series!("Medication", profile: @alice, starts_on: Date.new(2026, 10, 6), title: "Flu shot", kind: :injection, area: :arm, side: :left)
    dose = shot.occurrence_on(Date.new(2026, 10, 6)).tap(&:save!)
    shot.replace_uses_for!(dose, [ [ needles.id, "1" ] ])
    dose.reload.complete!
    stock = -> { [ needles, swabs ].map { SupplyPurchase.where(supply: _1).sum(:quantity_remaining).to_i } }
    assert_equal [ 9, 10 ], stock.call

    set = change!({ op: "update", type: "medication", ref: dose.id, fields: { uses: [ { supply: "Swabs", quantity: 2 } ] } })
    assert_equal [ 10, 8 ], stock.call
    assert_equal [ swabs.id ], dose.reload.own_details.supply_uses.map(&:supply_id)

    undo(set)
    assert_equal [ 9, 10 ], stock.call
    assert_equal [ needles.id ], dose.reload.own_details.supply_uses.map(&:supply_id)
  end

  def delete!(fields_or_ref)
    spec = { op: "delete" }.merge(fields_or_ref)
    data = Assistant::ChangeSets::Submit.call(chat: assistant_chat(@alice), operations: [ spec ], confirm: true)
    Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(data[:change_set_id]), confirmed: true)
    data
  end

  test "deleting a recipe, or a whole series from a day nothing was saved about, once pressed" do
    pesto = Recipe.create!(profile: @alice, name: "Pesto")
    delete!(type: "recipe", ref: pesto.id)
    assert_not Recipe.exists?(pesto.id)

    delete!(type: "task", ref: "event_id #{@bins.id} on 2026-10-12", fields: { scope: "series" })
    assert_not Event.exists?(@bins.id), "the whole series goes"
  end

  test "deleting the saved days of several series says each keeps repeating" do
    plants = weekly_event(profile: @alice, type: "Task", starts_on: Date.new(2026, 10, 6), title: "Water the ferns")
    [ day!(@bins, date: Date.new(2026, 10, 5)), day!(plants, date: Date.new(2026, 10, 6)) ].then do |days|
      note = delete!(type: "task", fields: { ids: days.map(&:id) }).dig(:changes, 0, :notes).to_s
      assert_match "these series (event_id #{@bins.id}, #{plants.id}) keep repeating", note
    end
  end

  test "a one-off made to repeat; a medication's times changed go on from today, its past kept" do
    call = series!("Task", profile: @alice, starts_on: Date.new(2026, 10, 9), title: "Call mum")
    day = call.occurrence_on(Date.new(2026, 10, 9)).tap(&:save!)
    change!({ op: "update", type: "task", ref: day.id, fields: { recurrence: { frequency: "weekly" } } })
    assert_predicate call.reload, :recurring?

    twice = timed_medication!(profile: @alice, starts_on: Date.new(2026, 10, 1), times: %w[08:00 20:00]).event
    dose = twice.occurrences.find_by!(date: Date.new(2026, 10, 1))
    change!({ op: "update", type: "medication", ref: dose.id, fields: { recurrence: { times_of_day: %w[08:00 14:00 20:00] } } })
    assert_equal [ %w[08:00 20:00], "2026-10-06" ], [ twice.reload.slots.map(&:first), Events::RecurrenceRule.describe(twice.rrule)[:ends].to_s ],
                 "its past keeps its two doses, and it ended yesterday"
    from_today = Medication.find_by!(profile: @alice, title: twice.title, starts_on: Date.new(2026, 10, 7))
    assert_equal %w[08:00 14:00 20:00], from_today.slots.map(&:first)
  end

  test "a series' times changed along with a dose go on from today too, and undo brings the one series back" do
    twice = timed_medication!(profile: @alice, starts_on: Date.new(2026, 10, 1), times: %w[08:00 20:00]).event
    dose = twice.occurrences.find_by!(date: Date.new(2026, 10, 1))
    set = change!({ op: "update", type: "medication", ref: dose.id, fields: { quantity: 2, recurrence: { times_of_day: %w[09:00 21:00] } } })

    from_today = Medication.find_by!(profile: @alice, title: twice.title, starts_on: Date.new(2026, 10, 7))
    assert_equal [ 2, %w[08:00 20:00], %w[09:00 21:00] ], [ dose.reload.details.quantity, twice.reload.slots.map(&:first), from_today.slots.map(&:first) ]

    undo(set)
    assert_not Event.exists?(from_today.id)
    assert_nil Events::RecurrenceRule.describe(twice.reload.rrule)[:ends], "the series goes on as it did"
    assert_nil dose.reload.details.quantity
  end

  test "values for a lab test's upcoming day save the day with them; undo leaves it unsaved again" do
    checkups = weekly_event(profile: @alice, type: "LabTestResult", starts_on: Date.new(2026, 10, 5), title: "Checkup")
    set = change!({ op: "update", type: "lab_test_result", ref: "event_id #{checkups.id} on 2026-10-12", fields: { values: { "Ferritin" => "45" } } })

    day = checkups.occurrences.sole
    assert_equal [ Date.new(2026, 10, 12), "45" ], [ day.date, day.lab_test_result_entries.sole.value.to_s ]

    undo(set)
    assert_empty checkups.occurrences.reload
  end
end
