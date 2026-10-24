# frozen_string_literal: true

require "test_helper"

class LabTestResultEntryTest < ActiveSupport::TestCase
  test "belongs to the day it was measured" do
    entry = lab_test_result_entries(:glucose)
    assert_equal occurrences(:bloodwork_done), entry.occurrence
  end

  test "requires an analyte" do
    entry = LabTestResultEntry.new(occurrence: occurrences(:bloodwork_due), value: "1")
    assert_not entry.valid?
    assert_includes entry.errors[:analyte], "can't be blank"
  end

  test "requires a value" do
    entry = LabTestResultEntry.new(occurrence: occurrences(:bloodwork_due), analyte: analytes(:glucose), value: nil)
    assert_not entry.valid?
    assert_includes entry.errors[:value], "can't be blank"
  end

  test "enforces unique analyte per day" do
    duplicate = LabTestResultEntry.new(
      occurrence: lab_test_result_entries(:glucose).occurrence,
      analyte: analytes(:glucose),
      value: "100"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:analyte_id], "has already been taken"
  end

  test "allows the same analyte across different days" do
    entry = LabTestResultEntry.new(occurrence: occurrences(:bloodwork_due), analyte: analytes(:glucose), value: "100")
    assert_predicate entry, :valid?
  end

  test "analyte_name= resolves to an existing analyte idempotently" do
    entry = LabTestResultEntry.new(occurrence: occurrences(:bloodwork_due), value: "100")
    entry.analyte_name = "glucose" # different case than the fixture's "Glucose"
    entry.valid?
    assert_equal analytes(:glucose), entry.analyte
  end

  test "analyte_name= makes a new analyte when none matches: on save, never on a check" do
    entry = LabTestResultEntry.new(occurrence: occurrences(:bloodwork_due), value: "1")
    entry.analyte_name = "Brand New Analyte"
    assert_no_difference(-> { Analyte.count }) { assert_predicate entry, :valid? }
    assert_difference(-> { Analyte.count }, 1) { entry.save! }
    assert_equal "Brand New Analyte", entry.analyte.name
  end

  test "unit_name= resolves to an existing unit idempotently" do
    entry = LabTestResultEntry.new(occurrence: occurrences(:bloodwork_due), analyte: analytes(:glucose), value: "100")
    entry.unit_name = "MG/DL"
    entry.valid?
    assert_equal units(:mgdl), entry.unit
  end

  test "unit is optional" do
    entry = LabTestResultEntry.new(occurrence: occurrences(:bloodwork_due), analyte: analytes(:tsh), value: "2.1")
    assert_predicate entry, :valid?
  end

  # ── #flag ──────────────────────────────────────────────────────────────

  test "flag is normal when value is within the applicable range" do
    entry = lab_test_result_entries(:glucose) # 95, and Alice has no gender set, so the "any" range of 70-100 applies
    assert_equal :normal, entry.flag
  end

  test "flag is low when value is below the low bound" do
    entry = lab_test_result_entries(:glucose)
    entry.value = "60"
    assert_equal :low, entry.flag
  end

  test "flag is high when value is above the high bound" do
    entry = lab_test_result_entries(:glucose)
    entry.value = "150"
    assert_equal :high, entry.flag
  end

  test "flag is abnormal past a critical threshold" do
    entry = lab_test_result_entries(:glucose)
    entry.value = "30"
    assert_equal :abnormal, entry.flag

    entry.value = "500"
    assert_equal :abnormal, entry.flag
  end

  test "flag prefers a sex-specific range over the any-range" do
    entry = lab_test_result_entries(:glucose)
    entry.occurrence.event.profile.update!(gender: :male)
    entry.value = "80" # within both the "any" range (70-100) and the male one (74-106)
    assert_equal :normal, entry.flag

    entry.value = "72" # below male low (74) but within any-range low (70) -> proves male range is actually used
    assert_equal :low, entry.flag
  end

  test "flag falls back to the any-range for a non_binary profile" do
    entry = lab_test_result_entries(:glucose)
    entry.occurrence.event.profile.update!(gender: :non_binary)
    entry.value = "72" # below male-only low (74) but within any-range (70-100)
    assert_equal :normal, entry.flag
  end

  test "flag is nil when there is no unit" do
    entry = lab_test_result_entries(:glucose)
    entry.unit = nil
    assert_nil entry.flag
  end

  # Just past the high bound of 100: read as 1005 or as 100 it would be
  # flagged otherwise.
  test "a value typed with a decimal comma is flagged like one typed with a point" do
    entry = lab_test_result_entries(:glucose)
    entry.value = "100,5"

    assert_equal :high, entry.flag
    assert_equal "100,5", entry.value
  end

  test "flag is nil when the value is not numeric" do
    entry = lab_test_result_entries(:glucose)
    entry.value = "Hemolyzed"
    assert_nil entry.flag
  end

  test "flag is nil when no reference range is defined" do
    entry = lab_test_result_entries(:cholesterol) # no reference_ranges fixture for cholesterol
    assert_nil entry.flag
  end

  # ── #numeric_value ─────────────────────────────────────────────────────

  test "numeric_value reads a decimal point or a decimal comma" do
    assert_in_delta 5.4, LabTestResultEntry.new(value: "5.4").numeric_value
    assert_in_delta 5.4, LabTestResultEntry.new(value: "5,4").numeric_value
    assert_in_delta 95.0, LabTestResultEntry.new(value: " 95 ").numeric_value
  end

  test "numeric_value is nil for a value that is words, and for one with both a comma and a point" do
    [ "<0.5", "positive", "1,250.5", "1.250,5", "" ].each do |value|
      assert_nil LabTestResultEntry.new(value: value).numeric_value, value
    end
  end
end
