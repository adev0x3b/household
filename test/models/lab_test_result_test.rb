# frozen_string_literal: true

require "test_helper"

class LabTestResultTest < ActiveSupport::TestCase
  test "requires a title" do
    result = LabTestResult.new(profile: profiles(:alice), starts_on: Date.current)
    assert_not result.valid?
    assert_includes result.errors[:title], "can't be blank"
  end

  test "belongs to healthcare and takes its fee there" do
    assert_equal :healthcare, LabTestResult.section
    assert_equal :healthcare, LabTestResult.fee_category
    assert_instance_of LabTestResult::Details, events(:bloodwork).details
  end

  test "a day has many entries, which go with it" do
    day = occurrences(:bloodwork_done)
    assert_includes day.lab_test_result_entries, lab_test_result_entries(:glucose)

    ids = day.lab_test_result_entries.pluck(:id)
    Occurrence.delete_with_children([ day ])
    assert_empty LabTestResultEntry.where(id: ids)
  end

  test "a day accepts nested attributes to create new entries, resolving analyte/unit names" do
    day = occurrences(:bloodwork_due)
    day.update!(lab_test_result_entries_attributes: [ { analyte_name: "TSH", value: "2.1", unit_name: "mIU/L" } ])

    entry = day.lab_test_result_entries.joins(:analyte).find_by(analytes: { name: "TSH" })
    assert_not_nil entry
    assert_equal "2.1", entry.value
    assert_equal "mIU/L", entry.unit.name
  end

  test "a day accepts nested attributes to update and destroy existing entries" do
    day = occurrences(:bloodwork_done)
    glucose = lab_test_result_entries(:glucose)

    day.update!(lab_test_result_entries_attributes: [
                  { id: glucose.id, value: "110" },
                  { id: lab_test_result_entries(:cholesterol).id, _destroy: "1" }
                ])

    assert_equal "110", glucose.reload.value
    assert_not LabTestResultEntry.exists?(lab_test_result_entries(:cholesterol).id)
  end

  test "rejects nested rows where both analyte_name and value are blank" do
    day = occurrences(:bloodwork_due)
    assert_difference -> { day.lab_test_result_entries.count }, 0 do
      day.update!(lab_test_result_entries_attributes: [ { analyte_name: "", value: "" } ])
    end
  end

  test "rejects a batch of nested entries that share the same analyte" do
    day = occurrences(:bloodwork_due)
    assert_raises(ActiveRecord::RecordInvalid) do
      day.update!(lab_test_result_entries_attributes: [
                    { analyte_name: "Glucose", value: "95" },
                    { analyte_name: "glucose", value: "100" }
                  ])
    end
  end
end
