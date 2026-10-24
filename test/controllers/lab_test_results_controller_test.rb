# frozen_string_literal: true

require "test_helper"

class LabTestResultsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    sign_in @alice
    @report = occurrences(:bloodwork_due) # "Quarterly bloodwork", 2026-03-02
  end

  def entries_key = "lab_test_result[lab_test_result_entries_attributes]"

  # A new row the browser numbered itself ("-1") must survive the
  # controller's permit, and only an index that looks like an integer does:
  # a row under any other key never reaches the model.
  test "a new entry under a negative-integer index is saved; one under a made-up index is dropped" do
    patch event_day_path(@report.event, @report.date), as: :turbo_stream, params: {
      lab_test_result: { title: @report.title, lab_test_result_entries_attributes: {
        "-1" => { analyte_name: "Brand New", value: "2", unit_name: "mg/dL" },
        "new_1758099999999_1234" => { analyte_name: "Vanishes", value: "1", unit_name: "mg/dL" }
      } }
    }

    assert_response :success
    assert_equal([ "Brand New" ], @report.lab_test_result_entries.reload.map { _1.analyte.name })
  end

  test "a new report: its form for the day, then saved with its values, a typed analyte added to the catalog" do
    get new_lab_test_result_path(date: "2026-10-06"), as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals] form[action=?]", lab_test_results_path

    assert_difference -> { @alice.analytes.count }, 1 do
      post lab_test_results_path, as: :turbo_stream, params: {
        lab_test_result: { title: "Iron panel", date: "2026-10-06", lab_test_result_entries_attributes: {
          "-1" => { analyte_name: "glucose", value: "92", unit_name: "mg/dL" },
          "-2" => { analyte_name: "Ferritin", value: "40", unit_name: "ng/mL" }
        } },
        event: { frequency: "none" }
      }
    end
    assert_toast I18n.t("lab_test_results.notices.created")
    report = @alice.events.find_by!(title: "Iron panel").first_occurrence
    assert_equal({ "Glucose" => 92, "Ferritin" => 40 }, report.lab_test_result_entries.to_h { [ _1.analyte.name, _1.value.to_i ] })
  end

  # Every request is watched for N+1 queries (test_helper.rb).
  test "a report of many values, its analytes known and new, is saved in one go" do
    values = [ %w[glucose 92 mg/dL], %w[Cholesterol 180 mg/dL], %w[TSH 2 mIU/L], %w[Ferritin 40 ng/mL], %w[Iron 90 ug/dL], %w[Transferrin 250 mg/dL] ]

    assert_difference -> { @alice.analytes.count }, 3 do
      post lab_test_results_path, as: :turbo_stream, params: {
        lab_test_result: { title: "Full panel", date: "2026-10-06", lab_test_result_entries_attributes: values.each_with_index.to_h { |(name, value, unit), i|
          [ (-i - 1).to_s, { analyte_name: name, value: value, unit_name: unit } ]
        } },
        event: { frequency: "none" }
      }
    end
    report = @alice.events.find_by!(title: "Full panel").first_occurrence
    assert_equal %w[Cholesterol Ferritin Glucose Iron TSH Transferrin], report.lab_test_result_entries.map { _1.analyte.name }.sort
  end

  test "values entered in the form are the day's, and the form shows them back" do
    get edit_event_day_path(@report.event, @report.date), as: :turbo_stream
    assert_select "template input[name='#{entries_key}[NEW_RECORD][analyte_name]']"
    assert_select ".nested-fields__headings span", text: I18n.t("lab_test_results.form.entries.value_label")
    assert_select "template input[name='#{entries_key}[NEW_RECORD][value]'][aria-label=?]", I18n.t("lab_test_results.form.entries.value_label")

    patch event_day_path(@report.event, @report.date), as: :turbo_stream, params: {
      lab_test_result: { title: @report.title, lab_test_result_entries_attributes: { "-1" => { analyte_name: "Cobalamin", value: "120", unit_name: "pg/mL" } } },
      event: { frequency: "none" }
    }

    assert_response :success
    entry = @report.lab_test_result_entries.reload.sole
    assert_equal [ "Cobalamin", "120" ], [ entry.analyte.name, entry.value.to_s ]

    get edit_event_day_path(@report.event, @report.date), as: :turbo_stream
    assert_select "input[name='#{entries_key}[#{entry.id}][analyte_name]'][value=Cobalamin]"
  end

  test "a value typed with a decimal comma is saved as typed and flagged" do
    patch event_day_path(@report.event, @report.date), as: :turbo_stream, params: {
      lab_test_result: { title: @report.title, lab_test_result_entries_attributes: { "-1" => { analyte_name: "Glucose", value: "312,5", unit_name: "mg/dL" } } },
      event: { frequency: "none" }
    }

    assert_response :success
    entry = @report.lab_test_result_entries.reload.sole
    assert_equal "312,5", entry.value
    assert_equal :abnormal, entry.flag
  end

  test "a saved report's card offers to add its cost, which opens a payment about that day" do
    get calendar_path(month: 3, year: 2026)
    add_cost = new_transaction_path(about_type: "Occurrence", about_id: @report.id, date: "2026-03-02")
    assert_select "#day_2026-03-02 a.lab-test-result-card__cost-btn[href=?]", add_cost

    get add_cost, as: :turbo_stream
    assert_response :success
    assert_select "input[type=hidden][name='transaction[details_attributes][about_type]'][value=Event]"
    assert_select "input[type=hidden][name='transaction[details_attributes][about_id]'][value=?]", @report.event_id.to_s

    post transactions_path, as: :turbo_stream, params: {
      transaction: { title: "Bloodwork fee", date: "2026-03-02",
                     details_attributes: { about_type: "Event", about_id: @report.event_id, amount: "45",
                                           kind: "expense", category: "healthcare", payment_method: "card" } },
      event: { frequency: "none" }
    }
    assert_equal [ "Bloodwork fee" ], @report.costs.map(&:title)

    get calendar_path(month: 3, year: 2026)
    assert_select "#day_2026-03-02 .lab-test-result-card .attached-cost .attached-cost__amount", text: /45/
    assert_select "#day_2026-03-02 .lab-test-result-card__cost-btn", 0
  end
end
