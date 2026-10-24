# frozen_string_literal: true

require "test_helper"

# Right after saving something, "it" and "the report" mean what this chat
# just saved, not a search of everything.
class Assistant::ChatReferencesTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12)
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
    AssistantEval::Seeds.two_lab_reports(@profile)
  end

  teardown { travel_back }

  def save_report(chat = @chat)
    result = run_tool(:record_lab_results, chat, date: "today", values: [ { analyte: "Ferritin", value: "40", unit: "ng/mL" } ])
    assert_equal "saved", result[:data][:status], result.inspect
    days_of(LabTestResult, @profile).joins(:lab_test_result_entries).find_by!(lab_test_result_entries: { value: "40" })
  end

  test "\"the test was done a week ago\" moves the report this chat just saved, in one call" do
    report = save_report

    result = run_tool(:update_record, @chat, type: "lab_test_result", ref: "the lab report", changes: { date: "a week ago" })

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal Date.new(2026, 9, 17), report.reload.date
    assert_equal Date.new(2026, 9, 17), report.event.starts_on, "a one-off's series moves with its day"
  end

  test "\"it\" is what this chat saved; a date it doesn't have yet still finds it" do
    report = save_report

    run_tool(:update_record, @chat, type: "lab_test_result", ref: "it", changes: { title: "Iron panel" })
    assert_equal "Iron panel", report.reload.title

    run_tool(:update_record, @chat, type: "lab_test_result", ref: "the report from 2026-09-01", changes: { notes: "fasting" })
    assert_equal "fasting", report.reload.notes
  end

  test "words that name another record still find that record" do
    save_report

    run_tool(:update_record, @chat, type: "lab_test_result", ref: "the TSH report", changes: { notes: "retest" })

    assert_equal "retest", days_of(LabTestResult, @profile).find_by!(date: Date.new(2026, 9, 21)).notes
  end

  test "another chat's saves don't count" do
    save_report(assistant_chat(@profile))

    result = run_tool(:update_record, @chat, type: "lab_test_result", ref: "the lab report", changes: { title: "x" })

    assert_equal "needs_input", result[:data][:status], result.inspect
  end

  test "a range's unit left out is read from what the user wrote next to the analyte" do
    save_report
    @chat.assistant_messages.create!(role: "user", content: "The references for Ferritin in ng/mL are 30 to 400. Iron is fine between 60 and 170.")

    result = run_tool(:set_reference_ranges, @chat, ranges: [ { analyte: "Ferritin", low: 30, high: 400 }, { analyte: "Iron", low: 60, high: 170 } ])

    assert_equal "ng/mL", ReferenceRange.joins(:analyte).find_by!(analytes: { name: "Ferritin", profile_id: @profile.id }).unit.name
    assert_equal [ "unit (for Iron)" ], result[:data][:changes].sole[:missing], result.inspect
  end

  test "a value ten times past a new range is pointed out as a likely typo, with how to fix it" do
    run_tool(:record_lab_results, @chat, date: "a week ago", values: [ { analyte: "Calcium", value: "300", unit: "mg/dL" },
                                                                       { analyte: "Vitamin D", value: "20", unit: "ng/mL" } ])

    calcium = run_tool(:set_reference_ranges, @chat, ranges: [ { analyte: "Calcium", unit: "mg/dL", low: 8.5, high: 10 } ])
    vitamin_d = run_tool(:set_reference_ranges, @chat, ranges: [ { analyte: "Vitamin D", unit: "ng/mL", low: 20, high: 50 } ])

    assert_match(/Calcium 300 mg\/dL \(lab_test_result id \d+, 2026-09-17\) is ten times outside.*update_record/,
                 calcium[:data][:saved].sole[:check].sole)
    assert_nil vitamin_d[:data][:saved].sole[:check]
  end
end
