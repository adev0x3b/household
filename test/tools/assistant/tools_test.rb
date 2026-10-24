# frozen_string_literal: true

require "test_helper"

class Assistant::ToolsTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @carol = profiles(:carol)
    @chat = assistant_chat(@alice)
    @friday = Date.new(2026, 9, 25)
    travel_to Time.zone.local(2026, 9, 22, 12)
  end

  teardown { travel_back }

  test "reads, then one typed tool per kind of change" do
    assert_equal %w[search_records get_record record_lab_results set_reference_ranges record_purchases book_appointment
                    record_payment add_task record_medication set_dose_supplies add_collection record_groceries add_ingredient add_recipe add_grocery_list plan_meals
                    update_record mark_done delete_records share],
                 Assistant::BookkeeperAgent::TOOLS.map(&:tool_name)
    assert_equal Assistant::BookkeeperAgent::TOOLS.size - 2, Assistant::ChangeTool.write_tool_names.size
  end

  test "a tool is found by its name and says how its line in the chat reads" do
    assert_equal Assistant::SearchRecordsTool, Assistant::BookkeeperAgent.tool_named("search_records")
    assert_nil Assistant::BookkeeperAgent.tool_named("gone")
    assert_equal "search_records", Assistant::SearchRecordsTool.activity_key
    assert_equal "change", Assistant::RecordPaymentTool.activity_key
  end

  test "search only sees the profile's own and shared records" do
    appointment!(profile: @carol, date: @friday, counterpart: "Moretti")
    mine = appointment!(profile: @alice, date: @friday, counterpart: "Moretti")

    result = run_tool(:search_records, @chat, type: "appointment", query: "doctor Moretti")

    assert_equal [ mine.id ], result[:data][:results].pluck(:id)
  end

  test "another profile's record is simply not found" do
    theirs = appointment!(profile: @carol, date: @friday)

    assert_match "not found", run_tool(:get_record, @chat, type: "appointment", id: theirs.id)[:error]
  end

  test "date searches include upcoming occurrences of a repeating series" do
    event = weekly_event(profile: @alice, type: "Appointment", starts_on: @friday - 7, title: "Physio", counterpart: "Rossi")
    day!(event, date: @friday - 7)

    upcoming = run_tool(:search_records, @chat, type: "appointment", date_from: @friday.iso8601, date_to: @friday.iso8601)[:data][:results].sole

    assert_nil upcoming[:id]
    assert upcoming[:upcoming]
    assert_equal event.id, upcoming[:event_id]
    assert_equal [ "Physio", "Rossi", "weekly" ], upcoming.values_at(:title, :counterpart, :repeats)
  end

  test "search results are capped" do
    30.times { |i| task!(profile: @alice, date: @friday, title: "Chore #{i}") }

    assert_equal Assistant::Resources::MAX_RESULTS, run_tool(:search_records, @chat, type: "task", query: "chore")[:data][:count]
  end

  test "book_appointment saves a complete, safe booking at once" do
    result = run_tool(:book_appointment, @chat, counterpart: "Moretti", date: "this friday", time: "11:00", amount: 50, payment_method: "card")

    assert result[:ok], result.inspect
    assert_equal "saved", result[:data][:status]
    appointment = appointments_with("Moretti").find_by!(date: @friday)
    assert_equal "11:00", appointment.formatted_start_time
    assert_equal [ "medical", "Appointment with Moretti" ], [ appointment.details.kind, appointment.event.title ]
    assert_predicate appointment.costs.sole, :pending?, "a future visit's fee is paid with the visit"
    assert_predicate @chat.change_sets.last, :applied?
  end

  test "missing details come back as needs_input; calling again with just them saves" do
    first = run_tool(:book_appointment, @chat, counterpart: "Moretti", date: "this friday")
    assert_equal "needs_input", first[:data][:status]
    assert_includes first[:data][:changes].sole[:missing], "appointment.start_time"
    assert_match "NOT SAVED YET", first[:data][:next]

    second = run_tool(:book_appointment, @chat, time: "11:00")
    assert_equal "saved", second[:data][:status], second.inspect
    assert_equal 1, appointments_with("Moretti").count
  end

  test "a possible duplicate waits; confirm only accepts warnings already shown" do
    appointment!(profile: @alice, date: @friday + 7, counterpart: "Moretti")
    booking = { counterpart: "Moretti", date: "this friday", time: "11:00" }

    assert_equal "waiting_for_user", run_tool(:book_appointment, @chat, **booking)[:data][:status]
    assert_equal "saved", run_tool(:book_appointment, @chat, **booking, confirm: true)[:data][:status]
  end

  test "record_lab_results keeps every value on one report" do
    result = run_tool(:record_lab_results, @chat, date: "a week ago",
                                                  values: [ { analyte: "Cobalamin", value: "250", unit: "pg/mL" }, { analyte: "Calcium", value: "3" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    report = days_of(LabTestResult, @alice).last
    assert_equal Date.new(2026, 9, 15), report.date
    assert_predicate report, :completed?, "a past report is saved as done"
    assert_equal %w[Calcium Cobalamin], report.lab_test_result_entries.map { |e| e.analyte.name }.sort
  end

  test "set_reference_ranges saves one range per analyte in one call" do
    result = run_tool(:set_reference_ranges, @chat, ranges: [ { analyte: "Calcium", unit: "mg/dL", low: 8.5, high: 10 },
                                                              { analyte: "Vitamin D", unit: "ng/mL", range_text: "good between 20 and 50" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    ranges = ReferenceRange.joins(:analyte).where(analytes: { profile_id: @alice.id }).index_by { |r| r.analyte.name }
    assert_equal [ 8.5, 10.0 ], [ ranges["Calcium"].low.to_f, ranges["Calcium"].high.to_f ]
    assert_equal [ 20.0, 50.0 ], [ ranges["Vitamin D"].low.to_f, ranges["Vitamin D"].high.to_f ]
  end

  test "record_purchases saves every item with the shared payment and therapy, once the housemate who shares it is named" do
    result = run_tool(:record_purchases, @chat, therapy: "B12", payment_method: "card",
                                                items: [ { supply: "Needles", quantity: 100, amount: 12 }, { supply: "Syringes", quantity: 50, amount: 8 } ])

    assert_equal "waiting_for_user", result[:data][:status], result.inspect
    assert_equal([ [ "Bob" ], [ "Bob" ] ], result[:data][:changes].map { |change| change[:seen_by] })
    Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(result[:data][:change_set_id]), confirmed: true)
    purchases = SupplyPurchase.accessible_by(@alice).includes(:supply, :collection)
    assert_equal %w[Needles Syringes], purchases.map { |p| p.supply.name }.sort
    assert(purchases.all? { |p| p.collection&.name == "B12" && paid_with(p.costs.sole) == "card" })
  end

  test "an argument left empty never overwrites what was said before" do
    run_tool(:book_appointment, @chat, counterpart: "Moretti", date: "this friday", amount: 50)
    run_tool(:book_appointment, @chat, counterpart: "", time: "11:00", payment_method: "card")

    appointment = appointments_with("Moretti").sole
    assert_equal 50, amount_of(appointment.costs.sole).to_i
  end

  test "mark_done completes a visit by the user's words, and its fee with it" do
    run_tool(:book_appointment, @chat, counterpart: "Moretti", date: "today", time: "11:00", amount: 50, payment_method: "card")

    result = run_tool(:mark_done, @chat, type: "appointment", ref: "Moretti visit today")

    assert_equal "saved", result[:data][:status], result.inspect
    appointment = appointments_with("Moretti").sole
    assert_predicate appointment, :completed?
    assert_predicate appointment.costs.sole, :completed?
  end

  test "done on the day picks the visit due today among several matches" do
    appointment!(profile: @alice, date: @friday + 7, counterpart: "Moretti")
    visit = appointment!(profile: @alice, date: @friday, counterpart: "Moretti")
    travel_to @friday.in_time_zone.change(hour: 12)

    result = run_tool(:mark_done, @chat, type: "appointment", ref: "Moretti")

    assert_equal "saved", result[:data][:status], result.inspect
    assert_predicate visit.reload, :completed?
  end

  test "a corrected reference replaces the one that matched several" do
    appointment!(profile: @alice, date: @friday + 7, counterpart: "Moretti")
    visit = appointment!(profile: @alice, date: @friday, counterpart: "Moretti")

    assert_equal "needs_input", run_tool(:mark_done, @chat, type: "appointment", ref: "Moretti")[:data][:status]
    result = run_tool(:mark_done, @chat, type: "appointment", ref: "Moretti on September 25, 2026")

    assert_equal "saved", result[:data][:status], result.inspect
    assert_predicate visit.reload, :completed?
    assert_equal 1, @chat.change_sets.last.operations.size
  end

  test "what is ready is saved even when something else still needs details" do
    assert_equal "needs_input", run_tool(:set_reference_ranges, @chat, ranges: [ { analyte: "Zinc", low: 60, high: 120 } ])[:data][:status]

    result = run_tool(:record_lab_results, @chat, date: "yesterday", values: [ { analyte: "Iron", value: "90" } ])

    assert_equal "needs_input", result[:data][:status], "the range still needs its unit"
    assert_equal "lab_test_result", result[:data][:saved].sole[:type]
    assert_match "saved part is done", result[:data][:next]
    assert_equal %w[applied open], @chat.change_sets.order(:id).map(&:status).last(2).sort
  end

  test "update_record takes lab values given inside changes too" do
    report = run_tool(:record_lab_results, @chat, date: "yesterday", values: [ { analyte: "Calcium", value: "300" } ])[:data][:saved].sole

    result = run_tool(:update_record, @chat, type: "lab_test_result", ref: report[:id].to_s, changes: { values: [ { analyte: "Calcium", value: "3" } ] })

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal "3", Occurrence.find(report[:id]).lab_test_result_entries.sole.value.to_s
  end

  test "update_record adds a value the report lacked, and passes over one it never had" do
    report = run_tool(:record_lab_results, @chat, date: "yesterday", values: [ { analyte: "Calcium", value: "9.5" } ])[:data][:saved].sole

    result = run_tool(:update_record, @chat, type: "lab_test_result", ref: report[:id].to_s,
                                             values: [ { analyte: "Ferritin", value: "45" } ], remove_values: [ "Zinc" ])

    assert_equal "saved", result[:data][:status], result.inspect
    entries = Occurrence.find(report[:id]).lab_test_result_entries.includes(:analyte)
    assert_equal({ "Calcium" => "9.5", "Ferritin" => "45" }, entries.to_h { |entry| [ entry.analyte.name, entry.value.to_s ] })
  end

  test "a range with one bound checks the values against it, past one that isn't a number" do
    run_tool(:record_lab_results, @chat, date: "2026-09-01", values: [ { analyte: "Ferritin", value: "1", unit: "ng/mL" } ])
    later = [ { analyte: "Ferritin", value: "trace", unit: "ng/mL" }, { analyte: "Iron", value: "90", unit: "µg/dL" } ]
    run_tool(:record_lab_results, @chat, date: "2026-09-08", values: later)

    result = run_tool(:set_reference_ranges, @chat, ranges: [ { analyte: "Ferritin", unit: "ng/mL", low: 15 }, { analyte: "Iron", unit: "µg/dL", high: 170 } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_match "Ferritin 1 ng/mL", result.inspect
    assert_match "ten times outside this range", result.inspect
    assert_nil result[:data][:saved].last[:check], "a value inside its range is no typo"
  end

  test "a range with critical bounds alone is saved without checking values against normal ones" do
    result = run_tool(:set_reference_ranges, @chat, ranges: [ { analyte: "Zinc", unit: "µg/dL", critical_high: 300 } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal 300, ReferenceRange.joins(:analyte).find_by!(analytes: { profile_id: @alice.id, name: "Zinc" }).critical_high
  end

  test "a lab report is found by the values in it" do
    report = run_tool(:record_lab_results, @chat, date: "yesterday", values: [ { analyte: "Calcium", value: "300" } ])[:data][:saved].sole

    result = run_tool(:update_record, @chat, type: "lab_test_result", ref: "Calcium: 300", values: [ { analyte: "Calcium", value: "3" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal "3", Occurrence.find(report[:id]).lab_test_result_entries.sole.value.to_s
  end

  test "ids written the way models write them are ids" do
    report = run_tool(:record_lab_results, @chat, date: "yesterday", values: [ { analyte: "Iron", value: "90" } ])[:data][:saved].sole

    [ "lab_test_result:#{report[:id]}", "##{report[:id]}", "id #{report[:id]}", "lab result #{report[:id]}" ].each do |ref|
      result = run_tool(:update_record, @chat, type: "lab_test_result", ref: ref, changes: { title: "Iron check #{ref}" })
      assert_equal "saved", result[:data][:status], "#{ref}: #{result.inspect}"
    end
  end

  test "a record the model describes wrongly is reported as its mistake" do
    result = run_tool(:update_record, @chat, type: "task", ref: "the chore", values: [ { analyte: "Calcium", value: "3" } ])

    assert_not result[:ok]
  end

  test "delete_records always waits for the button" do
    appointment = appointment!(profile: @alice, date: @friday)

    result = run_tool(:delete_records, @chat, type: "appointment", all: true)
    assert_equal "waiting_for_user", result[:data][:status]
    assert Occurrence.exists?(appointment.id)
    assert_match "give ref", run_tool(:delete_records, @chat, type: "appointment")[:error]
  end

  test "unknown types get a helpful error, common synonyms are understood" do
    assert_match "unknown type", run_tool(:search_records, @chat, type: "spaceship")[:error]
    assert_predicate run_tool(:search_records, @chat, type: "therapy", query: "B12")[:data][:results], :any?
  end

  test "every tool call is instrumented" do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("tool_call.assistant") { |event| events << event.payload }
    run_tool(:search_records, @chat, type: "task")
    run_tool(:get_record, @chat, type: "task", id: 0)

    assert_equal([ [ "search_records", true ], [ "get_record", false ] ], events.map { |e| [ e[:tool], e[:ok] ] })
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "a failure raised anywhere below a tool is its error to the model, and no bug report" do
    tool = Assistant::SearchRecordsTool.new(chat: @chat)
    tool.define_singleton_method(:execute) { |**| raise Assistant::Failure, "date must be YYYY-MM-DD" }

    assert_no_error_reported { assert_equal({ ok: false, error: "date must be YYYY-MM-DD" }, tool.call(type: "task")) }
  end

  test "an unexpected error inside a tool is reported to the model, not raised" do
    tool = Assistant::SearchRecordsTool.new(chat: @chat)
    tool.define_singleton_method(:execute) { |**| raise ActiveModel::UnknownAttributeError.new(Object.new, "target_ids") }

    report = assert_error_reported(ActiveModel::UnknownAttributeError) { assert_match "internal error in search_records", tool.call(type: "task")[:error] }
    assert_equal "search_records", report.context[:tool]
  end

  test "a write that fails part way saves none of it, and says nothing was changed" do
    assert_equal "needs_input", run_tool(:set_reference_ranges, @chat, ranges: [ { analyte: "Zinc", low: 60, high: 120 } ])[:data][:status]
    compile = Assistant::ChangeSets::Compiler.method(:call)
    sets = @chat.change_sets
    # What still waits is compiled again once the ready part is applied.
    after_saving = ->(set) { sets.applied.exists? ? raise(IOError, "the database went away") : compile.call(set) }

    result = nil
    assert_no_difference [ "LabTestResultEntry.count", "Assistant::ChangeSet.count" ] do
      assert_error_reported(IOError) do
        result = swapping(Assistant::ChangeSets::Compiler, :call, after_saving) do
          run_tool(:record_lab_results, @chat, date: "yesterday", values: [ { analyte: "Iron", value: "90" } ])
        end
      end
    end

    assert_not result[:ok]
    assert_match "nothing was changed", result[:error]
    assert_equal "open", @chat.change_sets.sole.status, "the range still waits for its unit"
  end
end
