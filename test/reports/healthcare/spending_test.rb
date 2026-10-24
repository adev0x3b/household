# frozen_string_literal: true

require "test_helper"

class Reports::Healthcare::SpendingTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2025, 3, 15)
    @march = period(Date.new(2025, 3, 1), Date.new(2025, 3, 31))
  end

  test "only completed healthcare expenses count as spent" do
    expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 5000)
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 700, status: :pending)
    expense!(profile: @profile, date: Date.new(2025, 3, 4), cents: 900, status: :cancelled)
    expense!(profile: @profile, date: Date.new(2025, 3, 5), cents: 1100, status: :skipped)
    expense!(profile: @profile, date: Date.new(2025, 3, 6), cents: 1300, category: :groceries)
    income!(profile: @profile, date: Date.new(2025, 3, 7), cents: 2000, category: :healthcare)

    assert_equal 5000, report.spend_metric.value.cents
  end

  test "a day's own amount, category and currency win over its series'" do
    series = weekly_event(profile: @profile, type: Transaction, starts_on: Date.new(2025, 3, 3), kind: :expense, category: :healthcare, amount: "10") # 3, 10, 17…
    day!(series, date: Date.new(2025, 3, 3), status: :completed)
    day!(series, date: Date.new(2025, 3, 10), status: :completed).write_details!(amount_cents: 2500)
    day!(series, date: Date.new(2025, 3, 11), status: :completed).write_details!(category: :groceries)

    assert_equal 3500, report.spend_metric.value.cents
  end

  test "currencies are reported separately, primary first" do
    expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 5000, currency: "EUR")
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 2000, currency: "USD")

    assert_equal "EUR", report.primary_currency
    assert_equal 5000, report.spend_metric.value.cents
    assert_equal([ [ "USD", 2000 ] ], report.other_currencies.map { |money| [ money.currency, money.cents ] })
  end

  test "an expense shared with several people is counted once" do
    transaction = expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 5000)
    EventShare.create!(event: transaction.event, profile: profiles(:alice))
    EventShare.create!(event: transaction.event, profile: profiles(:bob))

    assert_equal 5000, report.spend_metric.value.cents
  end

  test "a payment a housemate logged against the viewer is their income, not healthcare spending" do
    transfer!(payer: profiles(:bob), counterparty: @profile, date: Date.new(2025, 3, 2), cents: 5000, category: :healthcare)

    assert_not report.any?
    assert_equal 5000, report(profiles(:bob)).spend_metric.value.cents
  end

  test "scheduled covers pending days and the days of recurring expenses not stored yet, from today on" do
    expense!(profile: @profile, date: Date.new(2025, 3, 20), cents: 700, status: :pending)
    series = weekly_event(profile: @profile, type: Transaction, starts_on: Date.new(2025, 3, 3), kind: :expense, category: :healthcare, amount: "10") # 3, 10, 17, 24, 31
    day!(series, date: Date.new(2025, 3, 3), status: :completed)
    day!(series, date: Date.new(2025, 3, 24), status: :completed)
    weekly_event(profile: @profile, type: Transaction, starts_on: Date.new(2025, 3, 3), kind: :expense, category: :housing, amount: "500")

    # pending 700 + the 17th and the 31st at the series' 1000 each (the 24th is stored)
    assert_equal 2700, report.scheduled.cents
  end

  test "spending by type follows what each expense pays for" do
    visit = appointment!(profile: @profile, date: Date.new(2025, 3, 1))
    dose = medication!(profile: @profile, date: Date.new(2025, 3, 1))
    purchase = supply_purchase!(profile: @profile, name: "Needles")
    expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 5000, about: visit)
    expense!(profile: @profile, date: Date.new(2025, 3, 3), cents: 3000, about: dose.event)
    expense!(profile: @profile, date: Date.new(2025, 3, 4), cents: 1200, about: purchase)
    expense!(profile: @profile, date: Date.new(2025, 3, 5), cents: 800)

    totals = report.by_type_chart.series.to_h { |series| [ series.color, series.values.sum ] }

    assert_equal({ "series-1" => 50.0, "series-2" => 30.0, "series-3" => 12.0, "neutral" => 8.0 }, totals)
  end

  test "cost per therapy follows the paid-for series or purchase to its collection" do
    therapy = Collection.create!(profile: @profile, name: "B12")
    visit = appointment!(profile: @profile, date: Date.new(2025, 3, 1), collection: therapy)
    expense!(profile: @profile, date: Date.new(2025, 3, 2), cents: 5000, about: visit)
    purchase = supply_purchase!(profile: @profile, name: "Cobalamin vials", collection: therapy)
    expense!(profile: @profile, date: Date.new(2025, 3, 5), cents: 3000, about: purchase)
    expense!(profile: @profile, date: Date.new(2025, 3, 6), cents: 900, about: appointment!(profile: @profile, date: Date.new(2025, 3, 6)))

    row = report.collection_rows.sole

    assert_equal "B12", row.label
    assert_equal 8000, row.money.cents
    assert_equal 100, row.share
  end

  test "top supplies only count the selected period" do
    purchase = supply_purchase!(profile: @profile, name: "Needles")
    expense!(profile: @profile, date: Date.new(2025, 1, 5), cents: 9000, about: purchase)
    expense!(profile: @profile, date: Date.new(2025, 3, 5), cents: 1200, about: purchase)

    assert_equal([ [ "Needles", 1200 ] ], report.top_supply_rows.map { |row| [ row.label, row.money.cents ] })
  end

  private

  def report(viewer = @profile)
    Reports::Healthcare::Spending.new(audience: audience_for(viewer), period: @march, today: @today)
  end
end
