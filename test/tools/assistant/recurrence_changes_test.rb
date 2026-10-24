# frozen_string_literal: true

require "test_helper"

# Repeats through the assistant: changing a pattern "from now on" (the old
# series ends yesterday, a new one goes on from today — the past stays as it
# was), ending a
# series (its past occurrences stay), deleting a whole series, and repeats
# on new records.
class Assistant::RecurrenceChangesTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12) # Thursday; the seeded injection is weekly on Thursdays from Sep 3
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
    AssistantEval::Seeds.b12_injection_series(@profile)
    @series = Medication.where(profile: @profile).sole
  end

  teardown { travel_back }

  def medications = Medication.where(profile: @profile)
  def describe(event) = Events::RecurrenceRule.describe(event.reload.rrule)
  def september(event) = event.occurrence_dates_between(Date.new(2026, 9, 1), Date.new(2026, 9, 30))

  test "a new pattern from now on ends the old series yesterday and starts a new one today, keeping the therapy" do
    result = run_tool(:update_record, @chat, type: "medication", ref: "cobalamin", days: %w[monday thursday])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal Date.new(2026, 9, 23), describe(@series)[:ends]
    assert_equal [ 3, 10, 17 ].map { |d| Date.new(2026, 9, d) }, september(@series), "no past Monday turned into a missed dose"

    successor = medications.where.not(id: @series.id).sole
    assert_equal Date.new(2026, 9, 24), successor.starts_on, "today, a Thursday"
    assert_equal({ frequency: "weekly", interval: 1, week_days: %w[monday thursday] }, describe(successor))
    assert_equal @series.collection_id, successor.collection_id
    assert_equal [ "Cobalamin injection", "injection", "thigh" ], [ successor.title, successor.details.kind, successor.details.area ]

    Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))
    assert_nil describe(@series)[:ends]
    assert_equal 1, medications.count
  end

  test "a new pattern that would never happen is refused, and the series stays as it was" do
    result = run_tool(:update_record, @chat, type: "medication", ref: "cobalamin", days: %w[monday], ends: "today")

    assert_match "the new repeat never happens", result.inspect
    assert_nil describe(@series)[:ends]
    assert_equal 1, medications.count
  end

  test "stopping after today ends the series and keeps every past occurrence" do
    result = run_tool(:update_record, @chat, type: "medication", ref: "cobalamin", ends: "today")

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal Date.new(2026, 9, 24), describe(@series)[:ends]
    assert_equal [ 3, 10, 17, 24 ].map { |d| Date.new(2026, 9, d) }, september(@series)
    assert_empty @series.occurrence_dates_between(Date.new(2026, 9, 25), Date.new(2026, 12, 31))
  end

  test "repeat details sent inside changes count too" do
    run_tool(:update_record, @chat, type: "medication", ref: "cobalamin", changes: { "ends" => "2026-10-01" })

    assert_equal Date.new(2026, 10, 1), describe(@series)[:ends]
  end

  test "changes[:repeats] (plural, the read-side key) is read the same as repeat" do
    result = run_tool(:update_record, @chat, type: "medication", ref: "cobalamin", changes: { "repeats" => "weekly", "days" => %w[monday thursday] })

    assert_equal "saved", result[:data][:status], result.inspect
    successor = medications.where.not(id: @series.id).sole
    assert_equal({ frequency: "weekly", interval: 1, week_days: %w[monday thursday] }, describe(successor))
  end

  test "a series' event_id works as ref, on update_record and delete_records alike" do
    result = run_tool(:update_record, @chat, type: "medication", event_id: @series.id, changes: { ends: "today" })

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal Date.new(2026, 9, 24), describe(@series)[:ends]

    result = run_tool(:delete_records, @chat, type: "medication", event_id: @series.id, whole_series: true)
    assert_equal "waiting_for_user", result[:data][:status], result.inspect
  end

  test "a whole series is deleted with the button" do
    result = run_tool(:delete_records, @chat, type: "medication", ref: "cobalamin", whole_series: true)
    assert_equal "waiting_for_user", result[:data][:status], result.inspect

    Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(result[:data][:change_set_id]), confirmed: true)
    assert_not Event.exists?(@series.id)
  end

  test "a new booking can repeat on chosen days" do
    result = run_tool(:book_appointment, @chat, counterpart: "Physio", kind: "personal", date: "2026-09-28", time: "18:00", days: %w[monday wednesday])

    assert_equal "saved", result[:data][:status], result.inspect
    physio = appointments_with("Physio").sole
    assert_equal({ frequency: "weekly", interval: 1, week_days: %w[monday wednesday] }, describe(physio.event))
    assert_equal [ "personal", :agenda ], [ physio.details.kind, physio.event.section ]
  end

  # The times of the day a series' doses are taken (its slots).
  def times(event) = event.reload.event_slots.map { |slot| slot.anchor || slot.time_string }

  test "a new medication taken twice a day is a daily series with its two times, its first dose on the first" do
    result = run_tool(:record_medication, @chat, name: "Metformin", kind: "pill", quantity: 500, unit: "mg", date: "today", times: %w[breakfast 20:00])

    assert_equal "saved", result[:data][:status], result.inspect
    dose = days_of(Medication, @profile).joins(:event).find_by!(events: { title: "Metformin" })
    assert_equal %w[CM 20:00], times(dose.event)
    assert_equal "daily", describe(dose.event)[:frequency]
    assert_equal [ "08:00", "CM" ], [ dose.time_string, dose.anchor ]
    assert_equal [ "08:00", "breakfast" ], result[:data][:saved].first.values_at(:time, :with)
    assert_match(/with breakfast and at 20:00/, Assistant::ChangeSet.find(result[:data][:change_set_id]).display.first["summary"])

    bad = run_tool(:record_medication, @chat, name: "Other", kind: "pill", date: "today", times: %w[sometime])
    assert_equal false, bad[:ok]
    assert_match(/can't read the time/, bad[:error])
  end

  test "changing the times of a series from now on splits it like a new pattern does, and Undo restores it" do
    metformin = Medication.new(title: "Metformin", starts_on: Date.new(2026, 9, 10), details_attributes: { kind: "pill" })
    Occurrences::Create.call(metformin, by: @profile, recurrence: { frequency: "daily", slots: %w[CM CV] })

    result = run_tool(:update_record, @chat, type: "medication", ref: "metformin", times: %w[08:00 14:00 20:00])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal Date.new(2026, 9, 23), describe(metformin)[:ends]
    assert_equal %w[CM CV], times(metformin), "the past keeps its doses"
    successor = medications.where.not(id: [ metformin.id, @series.id ]).sole
    assert_equal Date.new(2026, 9, 24), successor.starts_on
    assert_equal %w[08:00 14:00 20:00], times(successor)
    assert_equal "08:00", successor.first_occurrence.time_string

    Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))
    assert_nil describe(metformin)[:ends]
    assert_equal %w[CM CV], times(metformin)
    assert_equal 2, medications.count
  end

  test "times are only for a medication" do
    task = Task.new(title: "Water the plants", starts_on: Date.new(2026, 9, 24))
    Occurrences::Create.call(task, by: @profile, recurrence: { frequency: "daily" })

    result = run_tool(:update_record, @chat, type: "task", ref: "plants", changes: { "times" => %w[08:00 20:00] })

    assert_equal false, result[:ok]
    assert_match(/only for a medication/, result[:error])
  end
end
