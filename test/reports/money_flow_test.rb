# frozen_string_literal: true

require "test_helper"

class Reports::MoneyFlowTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @march = period(Date.new(2025, 3, 1), Date.new(2025, 3, 31))
  end

  test "a flow of one kind is a magnitude, in the currency most money moved in" do
    expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 30_00, currency: "USD")
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 50_00, currency: "EUR")

    spent = flow(kind: :expense)

    assert_equal Reports::Money.new(cents: 50_00, currency: "EUR"), spent.total
    assert_equal([ Reports::Money.new(cents: 30_00, currency: "USD") ], spent.other_currencies)
  end

  test "the net of both kinds keeps its sign" do
    income!(profile: @profile, date: Date.new(2025, 3, 2), cents: 20_00)
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 50_00)

    assert_equal(-30_00, flow.total.cents)
  end

  test "an empty period is shown in the previous period's currency, else the fallback" do
    expense!(profile: @profile, date: Date.new(2025, 2, 10), cents: 10_00, currency: "USD")

    assert_equal "USD", flow(kind: :expense).currency
    assert_equal "GBP", flow(kind: :income).currency
    assert_equal Reports::Money.zero("GBP"), flow(kind: :income).total
  end

  test "a category narrows the flow" do
    expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 10_00, category: :groceries)
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 99_00, category: :housing)

    assert_equal 10_00, flow(kind: :expense, category: :groceries).total.cents
  end

  test "its metric compares with the period before and has a point per bucket" do
    expense!(profile: @profile, date: Date.new(2025, 2, 10), cents: 10_00)
    expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 12_50)

    metric = flow(kind: :expense).metric(polarity: :neutral)

    assert_equal [ 12_50, 10_00 ], [ metric.value.cents, metric.previous.cents ]
    assert_equal 31, metric.series.size
    assert_in_delta 12.5, metric.series[1]
    assert_in_delta 12.5, metric.series.sum
  end

  private

  def flow(**filters)
    days = Reports::Window.new(audience_for(@profile)).transaction_days
    Reports::MoneyFlow.new(days, period: @march, fallback_currency: "GBP", **filters)
  end
end
