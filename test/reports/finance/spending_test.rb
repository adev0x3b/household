# frozen_string_literal: true

require "test_helper"

class Reports::Finance::SpendingTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @march = period(Date.new(2025, 3, 1), Date.new(2025, 3, 31))
  end

  test "only completed expenses count as spent, across every category" do
    expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 5000, category: :housing)
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 700, category: :groceries, status: :pending)
    expense!(profile: @profile, date: Date.new(2025, 3, 4), cents: 900, category: :groceries, status: :cancelled)
    expense!(profile: @profile, date: Date.new(2025, 3, 5), cents: 1100, category: :groceries, status: :skipped)
    expense!(profile: @profile, date: Date.new(2025, 3, 6), cents: 1300, category: :groceries)

    assert_equal 6300, report.total_metric.value.cents
  end

  test "a transfer to savings is money kept, not spent: out of the total, the categories and the largest expenses" do
    expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 5000, category: :housing, title: "Rent")
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 9000, category: :savings, title: "Savings")

    assert_equal 5000, report.total_metric.value.cents
    assert_equal [ "Housing" ], report.category_rows.map(&:label)
    assert_equal [ "Rent" ], report.top_transaction_rows.map(&:title)
  end

  test "currencies are reported separately, primary first" do
    expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 5000, currency: "EUR")
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 2000, currency: "USD")

    assert_equal "EUR", report.primary_currency
    assert_equal([ [ "USD", 2000 ] ], report.other_currencies.map { |money| [ money.currency, money.cents ] })
  end

  test "a category outside the fixed identity set folds into Other on the chart" do
    expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 5000, category: :entertainment)

    chart = report.by_category_chart

    assert_not chart.empty?
    assert_equal [ I18n.t("home.finance.spending.other") ], chart.series.map(&:label)
    assert_equal [ "neutral" ], chart.series.map(&:color)
  end

  test "an expense shared with several people is counted once" do
    transaction = expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 5000)
    EventShare.create!(event: transaction.event, profile: profiles(:alice))
    EventShare.create!(event: transaction.event, profile: profiles(:bob))

    assert_equal 5000, report.total_metric.value.cents
  end

  test "top transactions are the largest expenses first, this period only, each its day" do
    expense!(profile: @profile, date: Date.new(2025, 1, 5), cents: 9000)
    expense!(profile: @profile, date: Date.new(2025, 3, 5), cents: 1200, title: "Bus pass")
    big = expense!(profile: @profile, date: Date.new(2025, 3, 6), cents: 3000, category: :housing, title: "Rent")

    rows = report.top_transaction_rows

    assert_equal([ [ 3000, "Rent", I18n.t("transactions.category.housing") ], [ 1200, "Bus pass", I18n.t("transactions.category.healthcare") ] ],
                 rows.map { |row| [ row.money.cents, row.title, row.category ] })
    assert_equal big, rows.first.occurrence
  end

  test "a payment between housemates is the payer's expense and never the counterparty's" do
    transfer!(payer: profiles(:bob), counterparty: @profile, date: Date.new(2025, 3, 2), cents: 5000)

    assert_not report.any?
    payer = Reports::Finance::Spending.new(audience: audience_for(profiles(:bob)), period: @march)
    assert_equal 5000, payer.total_metric.value.cents
  end

  test "a day of a monthly bill counts its own amount when it differs" do
    bill = series!("Transaction", profile: @profile, starts_on: Date.new(2025, 1, 10), rrule: "FREQ=MONTHLY", title: "Electricity",
                                  kind: :expense, category: :utilities, amount: "60")
    day!(bill, date: Date.new(2025, 3, 10), status: :completed).write_details!(amount_cents: 84_00)

    assert_equal 84_00, report.total_metric.value.cents
    assert_equal [ "Electricity" ], report.top_transaction_rows.map(&:title)
  end

  private

  def report
    Reports::Finance::Spending.new(audience: audience_for(@profile), period: @march)
  end
end
