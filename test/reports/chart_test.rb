# frozen_string_literal: true

require "test_helper"

class Reports::ChartTest < ActiveSupport::TestCase
  test "rejects color tokens that aren't in the palette" do
    assert_raises(ArgumentError) do
      Reports::Chart.new(kind: :bar, title: "t", labels: [ "a" ], series: [ Reports::Chart::Series.new(label: "s", values: [ 1 ], color: "#ff0000") ])
    end
  end

  test "to_spec carries tokens, format and the target label" do
    chart = Reports::Chart.new(
      kind: :line, title: "Adherence", labels: [ "1 Mar" ], format: :percent, target: 80,
      series: [ Reports::Chart::Series.new(label: "Adherence", values: [ 75.0 ]) ],
    )

    spec = chart.to_spec
    assert_equal "series-1", spec[:series].first[:color]
    assert_equal :percent, spec[:format]
    assert_equal I18n.t("statistics.target_label"), spec[:target_label]
  end

  test "empty when every value is zero or missing" do
    chart = Reports::Chart.new(kind: :bar, title: "t", labels: %w[a b], series: [ Reports::Chart::Series.new(label: "s", values: [ 0, nil ]) ])

    assert_empty chart
  end

  test "a money chart's point is Money in its currency, any other chart's the value itself" do
    series = [ Reports::Chart::Series.new(label: "s", values: [ 12.345 ]) ]
    money = Reports::Chart.new(kind: :bar, title: "t", labels: [ "a" ], series: series, format: :money, currency: "EUR")
    count = Reports::Chart.new(kind: :bar, title: "t", labels: [ "a" ], series: series)

    assert_equal Reports::Money.new(cents: 1235, currency: "EUR"), money.point(12.345)
    assert_equal 7, count.point(7)
  end
end
