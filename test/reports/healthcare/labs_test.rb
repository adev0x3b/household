# frozen_string_literal: true

require "test_helper"

class Reports::Healthcare::LabsTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    analytes(:glucose).update!(profile: @profile) # with its reference ranges
    @march = period(Date.new(2025, 3, 1), Date.new(2025, 3, 31))
  end

  test "counts out-of-range values with the same flags as the entry itself" do
    lab_result(Date.new(2025, 3, 3), "65")   # low
    lab_result(Date.new(2025, 3, 10), "90")  # normal
    lab_result(Date.new(2025, 3, 17), "300") # past critical high

    report = build_report

    assert_equal 2, report.out_of_range_metric.value
    assert_equal 1, report.critical_count
    row = report.analyte_rows.sole
    assert_equal :abnormal, row.latest.flag
    assert_equal [ 65.0, 90.0, 300.0 ], row.trend
    assert_equal LabTestResultEntry.where(value: "300").sole.flag, row.latest.flag
  end

  test "a value typed with a decimal comma is flagged and charted like one typed with a point" do
    lab_result(Date.new(2025, 3, 3), "100,5")

    row = build_report.analyte_rows.sole

    assert_equal :high, row.latest.flag
    assert_equal "100,5", row.latest.value
    assert_equal [ 100.5 ], row.trend
  end

  test "cancelled and skipped results don't count, pending ones with values do" do
    lab_result(Date.new(2025, 3, 3), "300", status: :cancelled)
    lab_result(Date.new(2025, 3, 4), "300", status: :skipped)

    assert_not build_report.any?

    lab_result(Date.new(2025, 3, 5), "65", status: :pending)

    assert_equal 1, build_report.out_of_range_metric.value
  end

  test "values are dated by their day, even on a repeating series" do
    event = weekly_event(profile: @profile, type: LabTestResult, starts_on: Date.new(2025, 2, 24), title: "Bloods") # Mondays
    [ [ Date.new(2025, 2, 24), "65" ], [ Date.new(2025, 3, 3), "90" ], [ Date.new(2025, 3, 10), "120" ] ].each do |date, value|
      day = day!(event, date: date, status: :completed)
      LabTestResultEntry.create!(occurrence: day, analyte: analytes(:glucose), unit: units(:mgdl), value: value)
    end

    row = build_report.analyte_rows.sole

    assert_equal [ Date.new(2025, 3, 3), Date.new(2025, 3, 10) ], row.readings.map(&:date)
    assert_equal :high, row.latest.flag
  end

  test "someone else's results never count" do
    analytes(:glucose).update!(profile: profiles(:alice))
    event = series!("LabTestResult", profile: profiles(:alice), starts_on: Date.new(2025, 3, 3), title: "Bloods")
    LabTestResultEntry.create!(occurrence: day!(event, date: Date.new(2025, 3, 3), status: :completed), analyte: analytes(:glucose), unit: units(:mgdl), value: "300")

    assert_not build_report.any?
  end

  private

  def build_report
    Reports::Healthcare::Labs.new(audience: audience_for(@profile), period: @march, today: Date.new(2025, 3, 31))
  end

  def lab_result(date, value, status: :completed)
    event = series!("LabTestResult", profile: @profile, starts_on: date, title: "Bloods")
    LabTestResultEntry.create!(occurrence: day!(event, date: date, status: status), analyte: analytes(:glucose), unit: units(:mgdl), value: value)
  end
end
