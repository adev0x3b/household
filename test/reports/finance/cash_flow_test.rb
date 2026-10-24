# frozen_string_literal: true

require "test_helper"

class Reports::Finance::CashFlowTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @march = period(Date.new(2025, 3, 1), Date.new(2025, 3, 31))
  end

  test "net cash flow is income minus expenses, and can be negative" do
    income!(profile: @profile, date: Date.new(2025, 3, 2), cents: 100_00)
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 150_00)

    metric = report.net_cash_flow_metric

    assert_equal(-5000, metric.value.cents)
    assert_predicate metric.value, :negative?
  end

  test "a transfer to savings is neither income nor an expense of the cash flow" do
    income!(profile: @profile, date: Date.new(2025, 3, 2), cents: 100_00)
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 30_00, category: :savings)

    assert_equal 100_00, report.net_cash_flow_metric.value.cents
  end

  test "a payment between housemates nets out from each side" do
    transfer!(payer: @profile, counterparty: profiles(:bob), date: Date.new(2025, 3, 2), cents: 30_00)

    assert_equal(-30_00, report.net_cash_flow_metric.value.cents)
    assert_equal 30_00, report(profiles(:bob)).net_cash_flow_metric.value.cents
  end

  test "pending and cancelled entries don't affect net cash flow" do
    income!(profile: @profile, date: Date.new(2025, 3, 2), cents: 100_00)
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 999_00, status: :pending)

    assert_equal 100_00, report.net_cash_flow_metric.value.cents
  end

  test "savings rate is savings-category expense over income" do
    income!(profile: @profile, date: Date.new(2025, 3, 2), cents: 100_00)
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 20_00, category: :savings)
    expense!(profile: @profile, date: Date.new(2025, 3, 4), cents: 30_00, category: :groceries)

    assert_in_delta(20.0, report.savings_rate_metric.value)
  end

  test "savings rate is nil, not zero, when there is no income to divide by" do
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 20_00, category: :savings)

    assert_nil report.savings_rate_metric.value
    assert_equal I18n.t("statistics.no_data"), Statistics::Format.value(report.savings_rate_metric.value, :percent)
  end

  test "savings rate target is met at or above 20%" do
    income!(profile: @profile, date: Date.new(2025, 3, 2), cents: 100_00)
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 20_00, category: :savings)

    assert_predicate report.savings_rate_metric, :target_met?
  end

  private

  def report(viewer = @profile)
    Reports::Finance::CashFlow.new(audience: audience_for(viewer), period: @march)
  end
end
