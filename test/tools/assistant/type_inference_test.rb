# frozen_string_literal: true

require "test_helper"

# `type` left out is filled in when there's nothing to guess about: event_id
# names an Event, whose kind (Event#type) says exactly what it is; values /
# remove_values exist on nothing but a lab report. Read from saved eval
# runs, where the model gave event_id (or values) and left type out —
# 47 of 58 mark_done failures, and several of update_record's, were exactly this.
class Assistant::TypeInferenceTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12) # a Thursday: a dose is due
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
    AssistantEval::Seeds.b12_injection_series(@profile)
    @series = Medication.where(profile: @profile).sole
  end

  teardown { travel_back }

  test "mark_done infers type from event_id" do
    result = run_tool(:mark_done, @chat, event_id: @series.id)

    assert_equal "saved", result[:data][:status], result.inspect
    assert_predicate @series.occurrence_on(Date.new(2026, 9, 24)), :completed?
  end

  test "update_record infers type from event_id" do
    result = run_tool(:update_record, @chat, event_id: @series.id, changes: { ends: "today" })

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal Date.new(2026, 9, 24), Events::RecurrenceRule.describe(@series.reload.rrule)[:ends]
  end

  test "update_record infers lab_test_result from values, with no type and no event_id" do
    AssistantEval::Seeds.two_lab_reports(@profile)

    result = run_tool(:update_record, @chat, ref: "the TSH report", values: [ { analyte: "TSH", value: "2.5" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal "2.5", LabTestResultEntry.joins(:analyte).find_by!(analytes: { name: "TSH" }).value
  end

  test "update_record infers lab_test_result from remove_values too" do
    AssistantEval::Seeds.two_lab_reports(@profile)

    result = run_tool(:update_record, @chat, ref: "the TSH report", remove_values: [ "TSH" ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_empty LabTestResultEntry.joins(:analyte).where(analytes: { name: "TSH" })
  end

  test "delete_records infers type from event_id" do
    result = run_tool(:delete_records, @chat, event_id: @series.id, whole_series: true)

    assert_equal "waiting_for_user", result[:data][:status], result.inspect
  end

  test "share infers type from event_id" do
    result = run_tool(:share, @chat, event_id: @series.id, with: AssistantEval::Seeds.household_member(@profile).first_name)

    assert_equal "waiting_for_user", result[:data][:status], result.inspect
  end

  test "with nothing to infer from, type is asked for plainly" do
    result = run_tool(:mark_done, @chat, ref: "cobalamin")

    assert_match(/give type, or event_id/, result.inspect)
  end

  test "book_appointment and record_payment accept and ignore a stray type" do
    booked = run_tool(:book_appointment, @chat, provider: "Moretti", date: "next Friday", time: "10:00", type: "appointment")
    assert_equal "saved", booked[:data][:status], booked.inspect
    assert_predicate appointments_with("Moretti"), :exists?, "provider is still read as the counterpart"

    paid = run_tool(:record_payment, @chat, title: "Rent", amount: 50, kind: "expense", payment_method: "cash",
                                            category: "housing", date: "today", type: "transaction")
    assert_equal "saved", paid[:data][:status], paid.inspect
  end
end
