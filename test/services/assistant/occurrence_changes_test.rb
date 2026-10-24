# frozen_string_literal: true

require "test_helper"

# The assistant works one day of a series at a time (an Occurrence): a
# one-off's fields are its series', a repeating series' day keeps its own
# (an override), a day moved off its date leaves the series' slot, and
# Undo puts every row back where it was.
class Assistant::OccurrenceChangesTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12) # a Thursday
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
  end

  teardown { travel_back }

  def undo(result) = Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))
  def apply(result) = Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(result[:data][:change_set_id]), confirmed: true)

  def weekly_rent
    rent = series!("Transaction", profile: @profile, starts_on: Date.new(2026, 9, 3), title: "Rent", rrule: "FREQ=WEEKLY",
                                  kind: :expense, category: :housing, amount: "500", currency: "EUR", payment_method: :bank_transfer)
    rent.update!(notes: "the flat")
    rent
  end

  test "a one-off's title goes on its series; Undo puts it back and unsaves the day" do
    visit = AssistantEval::Seeds.moretti_oct2(@profile).event
    visit.occurrences.destroy_all # made on the calendar, never touched

    result = run_tool(:update_record, @chat, type: "appointment", ref: "Moretti", changes: { title: "Follow-up", location: "Via Roma 1" })

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ "Follow-up", "Via Roma 1" ], visit.reload.values_at(:title, :location)
    day = visit.occurrences.sole
    assert_nil day.own_title, "the day reads it from its series"

    undo(result)
    assert_equal [ "Checkup", nil ], visit.reload.values_at(:title, :location)
    assert_empty visit.occurrences, "the day it saved is upcoming again"
  end

  test "a day of a repeating series keeps its own amount; the other days keep the series'" do
    rent = weekly_rent

    result = run_tool(:update_record, @chat, type: "transaction", ref: "event_id #{rent.id} on 2026-09-24", changes: { amount: 550, notes: "raised" })

    assert_equal "saved", result[:data][:status], result.inspect
    day = rent.occurrences.sole
    assert_equal [ 550, "raised" ], [ amount_of(day).to_i, day.notes ]
    assert_equal [ 500, "the flat" ], [ amount_of(rent.occurrence_on(Date.new(2026, 10, 1))).to_i, rent.reload.notes ]
    assert_equal 55_000, day.own_details.amount_cents, "a day's amount is how much, without a sign"

    undo(result)
    assert_empty rent.occurrences.reload
    assert_empty Transaction::Details.overrides.where(event_id: rent.id)
  end

  test "a day set to what its series says stores nothing of its own, so it keeps following the series" do
    rent = weekly_rent

    result = run_tool(:update_record, @chat, type: "transaction", ref: "event_id #{rent.id} on 2026-09-24", changes: { amount: 500, notes: "the flat", title: "Rent" })

    assert_equal "saved", result[:data][:status], result.inspect
    day = rent.occurrences.sole
    assert_nil day.own_title
    assert_nil day.own_notes
    assert_nil day.own_details&.own_amount_cents

    rent.details.update!(amount: "520")
    assert_equal 520, amount_of(day.reload).to_i, "the day follows the series' new amount"
  end

  test "who a repeating payment is with is the series', whichever day names it" do
    rent = weekly_rent
    marco = AssistantEval::Seeds.household_member(@profile)

    result = run_tool(:update_record, @chat, type: "transaction", ref: "event_id #{rent.id} on 2026-09-24", member: "Marco")

    assert_equal "waiting_for_user", result[:data][:status], "Marco will see the rent: #{result.inspect}"
    apply(result)
    assert_equal marco.id, rent.details.reload.counterparty_profile_id
    undo(result)
    assert_nil rent.details.reload.counterparty_profile_id
  end

  test "a saved day's own row is put back as it was, not removed" do
    rent = weekly_rent
    day = rent.occurrence_on(Date.new(2026, 9, 24))
    day.write_details!(payment_method: :cash)

    result = run_tool(:update_record, @chat, type: "transaction", ref: day.id.to_s, changes: { amount: 450 })
    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ 450, "cash" ], [ amount_of(day.reload).to_i, paid_with(day) ]

    undo(result)
    assert_equal [ 500, "cash" ], [ amount_of(day.reload).to_i, paid_with(day) ]
  end

  test "a day moved to another date leaves its slot; Undo brings it back" do
    AssistantEval::Seeds.b12_injection_series(@profile)
    series = Medication.where(profile: @profile).sole

    result = run_tool(:update_record, @chat, type: "medication", ref: "event_id #{series.id} on 2026-10-01", changes: { date: "2026-10-02" })

    assert_equal "saved", result[:data][:status], result.inspect
    october = ->(event) { event.reload.occurrences_between(Date.new(2026, 9, 28), Date.new(2026, 10, 4)).map(&:date) }
    assert_equal [ Date.new(2026, 10, 2) ], october.call(series), "not on the Thursday any more, nor twice"

    undo(result)
    assert_equal [ Date.new(2026, 10, 1) ], october.call(series)
    assert_empty series.event_exclusions.reload
  end

  test "a dose's supplies given with mark_done go on that dose alone, and Undo takes them back" do
    AssistantEval::Seeds.b12_injection_series(@profile)
    series = Medication.where(profile: @profile).sole
    dose = series.occurrence_on(Date.new(2026, 9, 24))
    dose.save! # saved before (a note, a reminder): its uses are restored, not dropped with it

    result = run_tool(:mark_done, @chat, type: "medication", ref: dose.id.to_s, uses: [ { supply: "needle" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal([ "Needles" ], dose.reload.details.resolved_uses.map { |use| use.supply.name })
    assert_empty series.details.supply_uses, "the series' plan is untouched"

    undo(result)
    assert_predicate dose.reload, :pending?
    assert_empty dose.details.resolved_uses
  end

  test "a day of a series is shown with its series, also before it is saved" do
    AssistantEval::Seeds.b12_injection_series(@profile)
    series = Medication.where(profile: @profile).sole

    shown = run_tool(:get_record, @chat, type: "medication", event_id: series.id, date: "2026-10-01")[:data]

    assert_equal [ nil, true, series.id, "2026-10-01", "weekly", "B12", "Cobalamin injection" ],
                 shown.values_at(:id, :upcoming, :event_id, :date, :repeats, :collection, :title)
  end

  test "records of a therapy are searched by its collection" do
    AssistantEval::Seeds.b12_injection_series(@profile)
    task!(profile: @profile, date: Date.new(2026, 9, 24), title: "Cobalamin refill")
    b12 = Collection.find_by!(profile: @profile, name: "B12")

    found = run_tool(:search_records, @chat, type: "medication", query: "cobalamin", collection_id: b12.id)[:data][:results]
    assert_predicate found, :any?
    assert(found.all? { |summary| summary[:collection] == "B12" })
    assert_empty run_tool(:search_records, @chat, type: "task", therapy_id: b12.id)[:data][:results]
  end

  test "a therapy is a collection: added, shared and named back in Healthcare's words" do
    marco = AssistantEval::Seeds.household_member(@profile)

    added = run_tool(:add_collection, @chat, name: "Physio", notes: "knee")
    assert_equal "saved", added[:data][:status], added.inspect
    physio = Collection.find_by!(profile: @profile, name: "Physio")
    assert_equal [ "healthcare", "knee" ], [ physio.section, physio.notes ]

    shared = run_tool(:share, @chat, type: "therapy", ref: "Physio", with: "Marco")
    Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(shared[:data][:change_set_id]), confirmed: true)
    assert_equal [ marco ], physio.shared_profiles.to_a
    assert_match "Therapies:\n- \"B12\"", Assistant::Context.new(@chat).to_prompt
  end

  test "an appointment of another kind is booked in its own section, named by who it's with" do
    result = run_tool(:book_appointment, @chat, kind: "work", counterpart: "Acme", title: "Interview", date: "2026-10-01", time: "15:00")

    assert_equal "saved", result[:data][:status], result.inspect
    day = appointments_with("Acme").sole
    assert_equal [ "work", :agenda, "Interview" ], [ day.details.kind, day.event.section, day.title ]
    assert_equal [ "Acme", "work" ], result[:data][:saved].sole.values_at(:counterpart, :kind)
  end
end
