# frozen_string_literal: true

require "test_helper"

class Reports::Healthcare::AppointmentsTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2025, 3, 15)
    @march = period(Date.new(2025, 3, 1), Date.new(2025, 3, 31))
  end

  test "attendance counts medical appointments only" do
    appointment!(profile: @profile, date: Date.new(2025, 3, 3), status: :completed, counterpart: "Dr Moretti")
    appointment!(profile: @profile, date: Date.new(2025, 3, 5), counterpart: "Dr Moretti")
    appointment!(profile: @profile, date: Date.new(2025, 3, 6), status: :cancelled)
    appointment!(profile: @profile, date: Date.new(2025, 3, 7), kind: :work, title: "Interview")

    assert_in_delta 50.0, report.attendance_metric.value
    assert_equal(3, report.status_chart.series.sum { |series| series.values.sum })
  end

  test "attendance per counterpart, read day by day: a day may see someone else" do
    series = weekly_event(profile: @profile, type: Appointment, starts_on: Date.new(2025, 3, 3), title: "Physio", kind: :medical, counterpart: "Anna") # 3, 10
    day!(series, date: Date.new(2025, 3, 3), status: :completed)
    day!(series, date: Date.new(2025, 3, 10), status: :completed).write_details!(counterpart: "Marco")
    appointment!(profile: @profile, date: Date.new(2025, 3, 4))

    rows = report.counterpart_rows.to_h { |row| [ row.counterpart, [ row.due, row.attended ] ] }

    assert_equal({ "Anna" => [ 1, 1 ], "Marco" => [ 1, 1 ], nil => [ 1, 0 ] }, rows)
  end

  test "coming up lists the next visits from today with who they're with" do
    appointment!(profile: @profile, date: @today + 3, counterpart: "Dr Moretti", title: "Endocrinologist")
    appointment!(profile: @profile, date: @today + 1, kind: :social, title: "Dinner")
    appointment!(profile: @profile, date: @today - 1, title: "Past")

    assert_equal([ [ @today + 3, "Endocrinologist", "Dr Moretti" ] ], report.upcoming.map { |row| [ row.date, row.title, row.counterpart ] })
  end

  private

  def report
    Reports::Healthcare::Appointments.new(audience: audience_for(@profile), period: @march, today: @today)
  end
end
