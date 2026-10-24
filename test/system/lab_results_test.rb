# frozen_string_literal: true

require "application_system_test_case"

# A lab report typed in from the paper: one row per value, added as they
# come (nested_fields_controller.js), each read against its reference
# range once saved. The card warns of a value out of range, and the form
# says which one.
class LabResultsTest < ApplicationSystemTestCase
  test "a report with several values warns on its card of the one out of range, and its form names it" do
    sign_in profiles(:alice)
    visit calendar_path

    add_to_day(Date.current, :lab_test_result)
    within(".modal") do
      fill_in I18n.t("lab_test_results.form.title_label"), with: "Quarterly bloodwork"
      enter_values([ "Glucose", "132", "mg/dL" ], [ "Cholesterol", "180", "mg/dL" ], [ "TSH", "2.1", "mIU/L" ])
      assert_accessible "a new lab report's form, with three values"
      click_on I18n.t("lab_test_results.form.create")
    end
    assert_text I18n.t("lab_test_results.notices.created")

    within_day(Date.current) do
      within(".lab-test-result-card", text: "Quarterly bloodwork") do
        assert_text I18n.t("lab_test_results.results_count", count: 3)
        assert_selector "[aria-label='#{I18n.t("lab_test_results.has_abnormal_result")}']"
        click_on "Quarterly bloodwork"
      end
    end
    within(".modal") do
      within(value_row("Glucose")) { assert_text I18n.t("lab_test_results.form.entries.flags.high") } # above 70–100 mg/dL
      within(value_row("Cholesterol")) { assert_no_selector ".status-badge" } # no range to read it against
      assert_accessible "a saved lab report, a value flagged"
    end
  end

  private

  # The form opens with one empty row; "Add value" gives the next.
  def enter_values(*values)
    values.each_with_index do |(analyte, value, unit), index|
      click_on I18n.t("lab_test_results.form.entries.add") if index.positive?
      within(all(".lab-entries__rows .lab-entry-row")[index]) do
        fill_in I18n.t("lab_test_results.form.entries.analyte_label"), with: analyte
        fill_in I18n.t("lab_test_results.form.entries.value_label"), with: value
        fill_in I18n.t("lab_test_results.form.entries.unit_label"), with: unit
      end
    end
  end

  def value_row(analyte)
    find(".lab-entries__rows .lab-entry-row") { _1.find_field(I18n.t("lab_test_results.form.entries.analyte_label")).value == analyte }
  end
end
