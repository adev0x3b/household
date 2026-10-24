# frozen_string_literal: true

require "test_helper"

class Reports::Finance::IncomeTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @march = period(Date.new(2025, 3, 1), Date.new(2025, 3, 31))
  end

  test "only completed income counts as received" do
    income!(profile: @profile, date: Date.new(2025, 3, 2), cents: 250_000, category: :salary)
    income!(profile: @profile, date: Date.new(2025, 3, 3), cents: 5000, category: :freelance, status: :pending)
    income!(profile: @profile, date: Date.new(2025, 3, 4), cents: 3000, category: :bonus, status: :cancelled)

    assert_equal 250_000, report.total_metric.value.cents
  end

  test "a housemate's payment logged against the viewer is the viewer's income" do
    transfer!(payer: profiles(:bob), counterparty: @profile, date: Date.new(2025, 3, 2), cents: 40_00, category: :refund)

    assert_equal 40_00, report.total_metric.value.cents
    assert_equal([ [ I18n.t("transactions.category.refund"), 40_00 ] ], report.category_rows.map { |row| [ row.label, row.money.cents ] })
  end

  test "currencies are reported separately, primary first" do
    income!(profile: @profile, date: Date.new(2025, 3, 2), cents: 250_000, currency: "EUR")
    income!(profile: @profile, date: Date.new(2025, 3, 3), cents: 40_000, currency: "USD")

    assert_equal "EUR", report.primary_currency
    assert_equal([ [ "USD", 40_000 ] ], report.other_currencies.map { |money| [ money.currency, money.cents ] })
  end

  test "each income category gets its own fixed series color" do
    income!(profile: @profile, date: Date.new(2025, 3, 2), cents: 250_000, category: :salary)
    income!(profile: @profile, date: Date.new(2025, 3, 3), cents: 10_000, category: :freelance)

    chart = report.by_category_chart

    colors = chart.series.to_h { |series| [ series.label, series.color ] }
    assert_equal "series-1", colors.fetch(I18n.t("transactions.category.salary"))
    assert_equal "series-2", colors.fetch(I18n.t("transactions.category.freelance"))
  end

  private

  def report
    Reports::Finance::Income.new(audience: audience_for(@profile), period: @march)
  end
end
