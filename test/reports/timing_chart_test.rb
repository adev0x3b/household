# frozen_string_literal: true

require "test_helper"

class Reports::TimingChartTest < ActiveSupport::TestCase
  test "counts each day of difference, gathering the far ends into the outer bars" do
    entries = [ done(days_late: 0), done(days_late: 1), done(days_late: 9), done(days_late: -4) ]

    chart = timing_chart(entries).to_chart

    assert_equal [ 1, 0, 1, 1, 0, 0, 1 ], chart.series.first.values
    assert_equal %w[series-1 series-1 series-1 good series-1 series-1 series-1], chart.series.first.colors
  end

  test "labels the bars late to early, the outer ones as at least that far" do
    labels = timing_chart([]).to_chart.labels

    assert_equal [
      "3 days late+", "2 days late", "1 day late", "On time", "1 day early", "2 days early", "3 days early+"
    ], labels
  end

  test "counts only what was done on a known day" do
    missed = entry(Occurrence.new(date: Date.new(2025, 3, 3)), :missed)
    undated = entry(Occurrence.new(date: Date.new(2025, 3, 3)), :taken)

    assert_not timing_chart([ missed, undated ]).any?
    assert_predicate timing_chart([ done(days_late: 0) ]), :any?
  end

  private

  def timing_chart(entries) = Reports::TimingChart.new(entries, title: "When", series_label: "Tasks")

  def done(days_late:)
    date = Date.new(2025, 3, 10)
    entry(Occurrence.new(date: date, completed_at: (date + days_late).in_time_zone.change(hour: 12)), :taken)
  end

  def entry(occurrence, state) = Reports::OccurrenceLedger::Entry.new(occurrence: occurrence, state: state)
end
