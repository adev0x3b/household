# frozen_string_literal: true

require "test_helper"

# Every day passed and still to do, however long ago (Reports::Unfinished):
# what "needs attention" lists, read without loading the done days.
class Reports::UnfinishedTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2026, 10, 9)
  end

  def unfinished(together: []) = Reports::Unfinished.new(audience_for(@profile), today: @today, together: together)

  test "a scheduled dose nothing was saved about, and a saved day still pending or in progress, until yesterday" do
    doses = series!("Medication", profile: @profile, starts_on: @today - 3, title: "Metformin", slots: %w[08:00 20:00],
                                  rrule: Events::RecurrenceRule.build(frequency: "daily"))
    day!(doses, date: @today - 3, time: "08:00", status: :completed)
    day!(doses, date: @today - 2, time: "20:00", status: :skipped)
    day!(doses, date: @today - 2, time: "08:00", status: :pending)
    doses.skip!(@today - 1)
    task!(profile: @profile, date: @today - 500, title: "Old", status: :in_progress)

    entries = unfinished.entries.map { [ _1.event.title, _1.date, _1.time, _1.record.present? ] }

    assert_equal [ [ "Old", @today - 500, nil, true ], [ "Metformin", @today - 3, "20:00", false ], [ "Metformin", @today - 2, "08:00", true ] ], entries
    assert(unfinished.entries.all? { _1.state == :missed })
  end

  test "each kind on its own ask, the series a block keeps; kinds named together are read at once" do
    task!(profile: @profile, date: @today - 2, title: "Bins")
    meal_on(@profile, @today - 1, title: "Soup")
    appointment!(profile: @profile, date: @today - 4, title: "Dinner", kind: :social)
    appointment!(profile: @profile, date: @today - 4, title: "Dentist", kind: :medical)

    reader = unfinished(together: [ Task, Meal, Appointment ])
    assert_equal [ "Bins" ], reader.entries(of: Task).map(&:label)
    assert_no_queries { assert_equal [ "Soup" ], reader.entries(of: Meal).map(&:label) }
    assert_equal [ "Dinner" ], reader.entries(of: Appointment) { _1.section == :agenda }.map(&:label)
  end

  test "latest: one per series, its newest unfinished day with how many it has, newest first" do
    bins = weekly_event(profile: @profile, type: Task, starts_on: @today - 21, title: "Bins") # -21, -14, -7 passed
    day!(bins, date: @today - 14, status: :completed)
    task!(profile: @profile, date: @today - 3, title: "Call")

    assert_equal([ [ "Call", @today - 3, 1 ], [ "Bins", @today - 7, 2 ] ], unfinished.latest(of: Task).map { |entry, count| [ entry.label, entry.date, count ] })
  end

  test "a series is read from the first day it may have nothing saved, not from its first day" do
    chores = series!("Task", profile: @profile, starts_on: @today - 400, title: "Plants", rrule: Events::RecurrenceRule.build(frequency: "daily"))
    chores.update_column(:unsaved_from, @today - 2)

    assert_equal [ @today - 2, @today - 1 ], unfinished.entries.map(&:date), "the days before the mark are taken as saved"
  end

  test "a series that starts today has nothing passed yet, nor one that starts tomorrow" do
    task!(profile: @profile, date: @today, title: "Today")
    task!(profile: @profile, date: @today + 1, title: "Tomorrow")

    assert_empty unfinished.entries
  end
end
