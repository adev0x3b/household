# frozen_string_literal: true

require "test_helper"

class Reports::CategoryChartTest < ActiveSupport::TestCase
  COLORS = { "housing" => "series-1", "groceries" => "series-2", nil => "neutral" }.freeze

  setup { @period = period(Date.new(2025, 3, 1), Date.new(2025, 3, 3)) }

  test "stacks each named category in its own colour, per bucket, as magnitudes" do
    chart = chart_of([ "housing", Date.new(2025, 3, 1) ] => -500_00, [ "housing", Date.new(2025, 3, 3) ] => -20_00)

    assert_equal :stacked_bar, chart.kind
    assert_equal [ [ "housing", "series-1", [ 500.0, 0.0, 20.0 ] ] ], drawn(chart)
  end

  test "gathers every category it doesn't name under the other series" do
    chart = chart_of([ "dining_out", Date.new(2025, 3, 2) ] => -15_00, [ "travel", Date.new(2025, 3, 2) ] => -5_00)

    assert_equal [ [ "other", "neutral", [ 0.0, 20.0, 0.0 ] ] ], drawn(chart)
  end

  test "leaves out a category with nothing in the period" do
    assert_empty chart_of({}).series
  end

  private

  def chart_of(totals)
    chart = Reports::CategoryChart.new(
      period: @period, totals: totals, colors: COLORS, currency: "EUR", title: "Spent",
    ) { |category| category || "other" }
    chart.to_chart
  end

  def drawn(chart)
    chart.series.map { |series| [ series.label, series.color, series.values ] }
  end
end
