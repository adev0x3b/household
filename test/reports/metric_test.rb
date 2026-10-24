# frozen_string_literal: true

require "test_helper"

class Reports::MetricTest < ActiveSupport::TestCase
  test "trend is judged by polarity, not by sign" do
    fewer_missed = Reports::Metric.new(value: 2, previous: 5, format: :count, polarity: :lower_is_better)
    lower_adherence = Reports::Metric.new(value: 70.0, previous: 90.0, format: :percent, polarity: :higher_is_better)
    more_spend = Reports::Metric.new(value: 10, previous: 5, format: :count, polarity: :neutral)

    assert_equal :improving, fewer_missed.trend
    assert_equal :down, fewer_missed.direction
    assert_equal :worsening, lower_adherence.trend
    assert_equal :neutral, more_spend.trend
  end

  test "no previous value means no comparison, not zero" do
    metric = Reports::Metric.new(value: 80.0, previous: nil, format: :percent, polarity: :higher_is_better)

    assert_not metric.comparable?
    assert_nil metric.delta
    assert_equal :flat, metric.trend
  end

  test "money in different currencies is not comparable" do
    metric = Reports::Metric.new(
      value: Reports::Money.new(cents: 100, currency: "EUR"), previous: Reports::Money.new(cents: 50, currency: "USD"),
      format: :money, polarity: :neutral,
    )

    assert_not metric.comparable?
  end

  test "the delta is the difference: a count's, or percentage points for a rate" do
    assert_equal 5, Reports::Metric.new(value: 15, previous: 10, format: :count, polarity: :neutral).delta
    assert_in_delta(-10.0, Reports::Metric.new(value: 70.0, previous: 80.0, format: :percent, polarity: :higher_is_better).delta)
  end

  test "rejects unknown formats and polarities" do
    assert_raises(ArgumentError) { Reports::Metric.new(value: 1, format: :ratio, polarity: :neutral) }
    assert_raises(ArgumentError) { Reports::Metric.new(value: 1, format: :count, polarity: :up) }
  end
end
