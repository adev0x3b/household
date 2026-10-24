# frozen_string_literal: true

require "test_helper"

class Reports::Agenda::AppointmentsTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2025, 3, 15)
  end

  test "attendance counts the appointments that aren't medical" do
    appointment!(profile: @profile, date: @today - 3, kind: :work, status: :completed, title: "Interview")
    appointment!(profile: @profile, date: @today - 4, kind: :social, title: "Dinner")
    appointment!(profile: @profile, date: @today - 5, kind: :personal, status: :cancelled, title: "Haircut")
    appointment!(profile: @profile, date: @today - 6, kind: :medical, title: "Checkup")
    appointment!(profile: @profile, date: @today - 40, kind: :work, status: :completed, title: "Earlier")

    metric = report.attendance_metric

    assert_in_delta 50.0, metric.value
    assert_in_delta 100.0, metric.previous
    assert_predicate report, :any?
  end

  test "attendance is nil, not 0%, when no appointment was due" do
    appointment!(profile: @profile, date: @today + 2, kind: :social)

    assert_nil report.attendance_metric.value
  end

  test "appointments coming up: the next 30 days, soonest first, with their kind and who they're with" do
    appointment!(profile: @profile, date: @today + 3, kind: :social, title: "Dinner", counterpart: "Giulia", start_time: "20:00")
    appointment!(profile: @profile, date: @today + 3, kind: :work, title: "Review", counterpart: "Acme", start_time: "09:30")
    appointment!(profile: @profile, date: @today, kind: :personal, title: "Haircut")
    appointment!(profile: @profile, date: @today + 31, kind: :work, title: "Too far")
    appointment!(profile: @profile, date: @today + 1, kind: :medical, title: "Checkup")
    appointment!(profile: @profile, date: @today + 2, kind: :social, title: "Done early", status: :completed)

    rows = report.upcoming_rows

    assert_equal([ [ @today, "Haircut", "personal", nil ], [ @today + 3, "Review", "work", "Acme" ], [ @today + 3, "Dinner", "social", "Giulia" ] ],
                 rows.map { |row| [ row.date, row.title, row.kind.name, row.counterpart ] })
    assert(rows.none? { |row| row.occurrence.projected? })
  end

  test "outcomes per bucket and attendance per kind" do
    appointment!(profile: @profile, date: @today - 3, kind: :work, status: :completed)
    appointment!(profile: @profile, date: @today - 4, kind: :work)
    appointment!(profile: @profile, date: @today - 5, kind: :social, status: :completed)
    appointment!(profile: @profile, date: @today - 6, kind: :social, status: :skipped)
    appointment!(profile: @profile, date: @today, kind: :social)

    chart = report.outcomes_chart
    totals = chart.series.to_h { |series| [ series.color, series.values.sum ] }

    assert_equal({ "good" => 2, "critical" => 1, "warning" => 1, "neutral" => 0, "series-1" => 1 }, totals)
    assert_equal [ [ "social", 2, 1, 50.0 ], [ "work", 2, 1, 50.0 ] ].sort,
                 report.kind_rows.map { |row| [ row.kind.name, row.due, row.attended, row.rate ] }.sort
  end

  private

  def report
    Reports::Agenda::Dashboard.new(audience: audience_for(@profile), period: Reports::Period.recent(today: @today), today: @today).appointments
  end
end
