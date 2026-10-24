# frozen_string_literal: true

require "test_helper"

class Reports::OccurrenceLedgerTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2025, 1, 20)
    @january = period(Date.new(2025, 1, 1), Date.new(2025, 1, 31))
  end

  test "a past scheduled date with no row is missed, not projected" do
    weekly_event(profile: @profile, type: Medication, starts_on: Date.new(2025, 1, 6)) # 6, 13, 20, 27

    entries = ledger.entries

    assert_equal([ [ 6, :missed ], [ 13, :missed ], [ 20, :due_today ], [ 27, :upcoming ] ], entries.map { |entry| [ entry.date.day, entry.state ] })
    assert entries.all? { |entry| entry.occurrence.projected? && entry.record.nil? }, "nothing stored: every day is an unsaved Occurrence"
  end

  test "a day still to come is today's not done yet or a later one, and charts as upcoming" do
    weekly_event(profile: @profile, type: Medication, starts_on: Date.new(2025, 1, 6)) # 6, 13, 20, 27

    entries = ledger.entries

    assert_equal [ false, false, true, true ], entries.map(&:to_come?)
    assert_equal %i[missed missed upcoming upcoming], entries.map(&:outcome)
  end

  test "classifies saved days by status" do
    event = weekly_event(profile: @profile, type: Medication, starts_on: Date.new(2025, 1, 1)) # 1, 8, 15, 22, 29
    medication!(profile: @profile, event: event, date: Date.new(2025, 1, 1), status: :completed, completed_on: Date.new(2025, 1, 1))
    medication!(profile: @profile, event: event, date: Date.new(2025, 1, 8), status: :completed, completed_on: Date.new(2025, 1, 10))
    medication!(profile: @profile, event: event, date: Date.new(2025, 1, 15), status: :skipped)
    medication!(profile: @profile, event: event, date: Date.new(2025, 1, 22), status: :cancelled)

    by_day = ledger.entries.index_by { |entry| entry.date.day }

    assert_equal :taken, by_day[1].state
    assert_equal :taken, by_day[8].state
    assert_equal :skipped, by_day[15].state
    assert_equal :cancelled, by_day[22].state
    assert_equal :upcoming, by_day[29].state
    assert_equal by_day[8].occurrence, by_day[8].record, "a saved day is its own record"
  end

  test "a day in progress is still not done" do
    event = weekly_event(profile: @profile, type: Task, starts_on: Date.new(2025, 1, 6), title: "Paint")
    day!(event, date: Date.new(2025, 1, 6), status: :in_progress)

    assert_equal :missed, ledger(Task).entries.first.state
  end

  test "rate is taken over due, ignoring cancelled and future days" do
    event = weekly_event(profile: @profile, type: Medication, starts_on: Date.new(2025, 1, 1))
    medication!(profile: @profile, event: event, date: Date.new(2025, 1, 1), status: :completed, completed_on: Date.new(2025, 1, 1))
    medication!(profile: @profile, event: event, date: Date.new(2025, 1, 15), status: :cancelled)
    # due: 1 (taken), 8 (missed) → 50%. 15 cancelled; 22 and 29 are in the future.

    assert_in_delta 50.0, ledger.rate
  end

  test "rate is nil when nothing was due" do
    weekly_event(profile: @profile, type: Medication, starts_on: Date.new(2025, 1, 27))

    assert_nil ledger.rate
  end

  test "includes a day that was moved off its schedule" do
    event = series!("Medication", profile: @profile, starts_on: Date.new(2024, 12, 20))
    medication!(profile: @profile, event: event, date: Date.new(2025, 1, 3), status: :completed, completed_on: Date.new(2025, 1, 3))

    assert_equal [ Date.new(2025, 1, 3) ], ledger.entries.map(&:date)
  end

  test "a day deleted from the series is gone" do
    event = weekly_event(profile: @profile, type: Medication, starts_on: Date.new(2025, 1, 6))
    event.skip!(Date.new(2025, 1, 13))

    assert_equal([ 6, 20, 27 ], ledger.entries.map { |entry| entry.date.day })
  end

  test "ignores series the viewer can't access" do
    weekly_event(profile: profiles(:bob), type: Medication, starts_on: Date.new(2025, 1, 6))

    assert_empty ledger.entries
  end

  test "takes any of the window's series: a section mixes kinds" do
    weekly_event(profile: @profile, type: Task, starts_on: Date.new(2025, 1, 6), title: "Bins")
    appointment!(profile: @profile, date: Date.new(2025, 1, 9), kind: :social, title: "Dinner")
    appointment!(profile: @profile, date: Date.new(2025, 1, 10), kind: :medical, title: "Checkup")

    agenda = Reports::Window.new(audience_for(@profile)).ledger(@january, today: @today) { _1.section == :agenda }

    assert_equal [ "Bins", "Dinner", "Bins", "Bins", "Bins" ], agenda.entries.map(&:label)
    assert_equal [ Task, Appointment ], agenda.by_event.keys.map(&:class)
  end

  test "reads a day's own details without a query per day" do
    event = weekly_event(profile: @profile, type: Task, starts_on: Date.new(2025, 1, 6), title: "Bins", priority: :low)
    day!(event, date: Date.new(2025, 1, 6), status: :completed).write_details!(priority: :urgent)
    day!(event, date: Date.new(2025, 1, 13), status: :completed)

    entries = ledger(Task).entries
    queries = count_queries { entries.map { |entry| entry.details.priority } }

    assert_equal(%w[urgent low low low], entries.map { |entry| entry.details.priority })
    assert_equal 0, queries
  end

  test "a medication taken at set times is one entry per dose, each on its own" do
    first = timed_medication!(profile: @profile, starts_on: Date.new(2025, 1, 19), times: %w[CM 20:00])
    first.complete!
    first.event.occurrence_for(Date.new(2025, 1, 19), time: "20:00").change_status!("skipped", reason: "forgot")
    untimed = medication!(profile: @profile, event: first.event, date: Date.new(2025, 1, 20), status: :completed, completed_on: Date.new(2025, 1, 20))

    entries = ledger.entries.select { |entry| entry.date <= Date.new(2025, 1, 20) }

    assert_equal([ [ 19, "08:00", "CM", :taken ], [ 19, "20:00", nil, :skipped ],
                   [ 20, nil, nil, :taken ], [ 20, "08:00", "CM", :due_today ], [ 20, "20:00", nil, :due_today ] ],
                 entries.map { |entry| [ entry.date.day, entry.time, entry.anchor, entry.state ] })
    assert_equal untimed, entries[2].record, "a dose saved without a time still counts"
    assert_in_delta 66.7, Reports::OccurrenceLedger.rate(entries)
  end

  private

  def ledger(type = Medication)
    Reports::Window.new(audience_for(@profile)).ledger(@january, today: @today, of: type)
  end
end
