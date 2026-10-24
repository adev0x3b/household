# frozen_string_literal: true

require "test_helper"

class Reports::Agenda::TasksTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2025, 3, 15)
  end

  test "completion is done over due: cancelled, today's and future tasks don't count" do
    task!(profile: @profile, date: @today - 3, status: :completed)
    task!(profile: @profile, date: @today - 4, status: :skipped)
    task!(profile: @profile, date: @today - 5)
    task!(profile: @profile, date: @today - 6, status: :cancelled)
    task!(profile: @profile, date: @today)
    task!(profile: @profile, date: @today + 2)

    assert_in_delta 33.3, report.completion_metric.value
    assert_equal 1, report.overdue_metric.value
    assert_equal 1, report.due_today_metric.value
  end

  test "with nothing due there is no rate, not 0%" do
    task!(profile: @profile, date: @today + 1)

    assert_nil report.completion_metric.value
    assert_equal 0, report.overdue_metric.value
  end

  test "a past date of a repeating task with no row is overdue, and opens as a projected day" do
    event = weekly_event(profile: @profile, type: Task, starts_on: @today - 14, title: "Laundry")
    task!(profile: @profile, date: @today - 14, status: :completed, event: event)

    overdue = report.overdue_rows

    assert_equal [ @today - 7 ], overdue.map(&:date)
    assert_equal "Laundry", overdue.first.title
    assert_predicate overdue.first.occurrence, :projected?
    assert_equal event, overdue.first.occurrence.event
    assert_equal [ @today, @today + 7 ], report.upcoming_rows.map(&:date)
  end

  test "the rate is compared with the 30 days before" do
    task!(profile: @profile, date: @today - 2, status: :completed)
    task!(profile: @profile, date: @today - 40)

    metric = report.completion_metric

    assert_in_delta(100.0, metric.value)
    assert_in_delta(0.0, metric.previous)
    assert_equal :improving, metric.trend
  end

  test "overdue rows put the most important first, then the oldest" do
    task!(profile: @profile, date: @today - 5, priority: :low, title: "Dust")
    task!(profile: @profile, date: @today - 2, priority: :urgent, title: "Boiler")
    task!(profile: @profile, date: @today - 20, priority: :high, title: "Old")

    assert_equal %w[Boiler Old Dust], report.overdue_rows.map(&:title)
  end

  test "a day's own priority and title win over its series'" do
    event = weekly_event(profile: @profile, type: Task, starts_on: @today - 7, title: "Bins", priority: :low)
    day = day!(event, date: @today - 7)
    day.update!(title: "Bins and glass")
    day.write_details!(priority: :urgent)

    row = report.overdue_rows.sole

    assert_equal [ "Bins and glass", "urgent" ], [ row.title, row.priority ]
  end

  test "today's progress counts what's done out of what's planned today" do
    task!(profile: @profile, date: @today, status: :completed)
    task!(profile: @profile, date: @today)
    task!(profile: @profile, date: @today, status: :cancelled)

    assert_equal({ done: 1, total: 2 }, report.today_progress)
  end

  test "the progress chart stacks done and not done over the period, with valid tokens" do
    task!(profile: @profile, date: @today - 1, status: :completed)
    task!(profile: @profile, date: @today - 8)
    task!(profile: @profile, date: @today)

    chart = report.progress_chart

    assert_equal :stacked_bar, chart.kind
    assert_equal 30, chart.labels.size
    assert_equal %w[good critical], chart.series.map(&:color)
    assert_equal([ 1, 1 ], chart.series.map { |series| series.values.sum })
  end

  test "a chosen period moves the rates and the charts, never what's coming up or overdue now" do
    task!(profile: @profile, date: Date.new(2025, 1, 10), status: :completed)
    task!(profile: @profile, date: Date.new(2025, 1, 20))
    task!(profile: @profile, date: @today - 2)
    task!(profile: @profile, date: @today + 1)
    january = report(period(Date.new(2025, 1, 1), Date.new(2025, 1, 31)))

    assert_in_delta(50.0, january.completion_metric.value)
    assert_equal 1, january.overdue_metric.value
    assert_equal [ @today - 2 ], january.overdue_rows.map(&:date)
    assert_equal [ @today + 1 ], january.upcoming_rows.map(&:date)
  end

  test "one row per task, the least kept up with first, with its next day" do
    event = weekly_event(profile: @profile, type: Task, starts_on: @today - 14, title: "Bins")
    task!(profile: @profile, date: @today - 14, status: :completed, event: event)
    task!(profile: @profile, date: @today - 3, status: :completed, title: "Bills")

    rows = report.series_rows

    assert_equal([ [ "Bins", 2, 1, 50.0, @today ], [ "Bills", 1, 1, 100.0, nil ] ], rows.map { |row| row.to_h.values })
  end

  test "timing counts how early or late tasks were done; priorities are ranked" do
    task!(profile: @profile, date: @today - 3, status: :completed, priority: :urgent)
    late = task!(profile: @profile, date: @today - 9, status: :completed, priority: :low)
    late.update!(completed_at: (@today - 4).in_time_zone.change(hour: 12))
    task!(profile: @profile, date: @today - 5, priority: :low)

    chart = report.timing_chart

    assert_predicate report, :timed?
    assert_equal [ 1, 0, 0, 1, 0, 0, 0 ], chart.series.first.values
    assert_equal "good", chart.series.first.colors[3]
    assert_equal([ [ "urgent", 1, 1, 100.0 ], [ "low", 2, 1, 50.0 ] ], report.priority_rows.map { |row| row.to_h.values })
  end

  test "someone else's tasks never count, shared ones count once" do
    task!(profile: profiles(:alice), date: @today - 2)
    shared = task!(profile: profiles(:alice), date: @today - 3)
    EventShare.create!(event: shared.event, profile: @profile)
    EventShare.create!(event: shared.event, profile: profiles(:bob))

    assert_equal 1, report.overdue_metric.value
  end

  private

  def report(period = nil)
    Reports::Agenda::Dashboard.new(audience: audience_for(@profile), period: period || Reports::Period.recent(today: @today), today: @today).tasks
  end
end
