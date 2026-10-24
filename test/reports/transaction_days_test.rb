# frozen_string_literal: true

require "test_helper"

class Reports::TransactionDaysTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @january = Date.new(2025, 1, 1)..Date.new(2025, 1, 31)
  end

  test "totals never add different currencies together" do
    expense!(profile: @profile, date: Date.new(2025, 1, 2), cents: 1000, currency: "EUR")
    expense!(profile: @profile, date: Date.new(2025, 1, 3), cents: 2500, currency: "EUR")
    expense!(profile: @profile, date: Date.new(2025, 1, 4), cents: 4000, currency: "USD")

    sums = days.totals(during: @january).by_currency

    assert_equal([ [ "USD", 4000 ], [ "EUR", 3500 ] ], sums.map { |money| [ money.currency, money.cents ] })
  end

  test "totals read a day's own amount and currency, else its series'" do
    expense!(profile: @profile, date: Date.new(2025, 1, 2), cents: 1000, currency: "EUR")
    expense!(profile: @profile, date: Date.new(2025, 1, 3), cents: 4000, currency: "USD").write_details!(amount_cents: 2500, currency: "EUR")

    sums = days.totals(during: @january).by_currency

    assert_equal([ [ "EUR", 3500 ] ], sums.map { |money| [ money.currency, money.cents ] })
    assert(sums.all? { |money| money.cents.is_a?(Integer) })
  end

  test "totals are filtered by dates, kind, category and currency, signed as the viewer reads them" do
    expense!(profile: @profile, date: Date.new(2025, 1, 2), cents: 1000, category: :groceries)
    expense!(profile: @profile, date: Date.new(2025, 1, 2), cents: 300, category: :healthcare)
    income!(profile: @profile, date: Date.new(2025, 1, 20), cents: 5000)
    expense!(profile: @profile, date: Date.new(2025, 1, 10), cents: 700, category: :groceries, status: :pending)

    totals = days.totals(during: @january)

    assert_equal 3700, totals.sum, "a pending day is no money yet"
    assert_equal({ "groceries" => -1000, "healthcare" => -300 }, totals.where(kind: :expense).sum_by(:category))
    assert_equal({ Date.new(2025, 1, 2) => -1300 }, totals.where(kind: :expense).sum_by(:date))
    assert_equal(-1000, totals.where(category: :groceries, currency: "EUR").sum)
    assert_equal 5000, days.totals(during: Date.new(2025, 1, 15)..Date.new(2025, 1, 31)).sum
  end

  test "every total inside the covered span comes from one query" do
    expense!(profile: @profile, date: Date.new(2025, 1, 2), cents: 1000)
    days = self.days.cover(Date.new(2024, 12, 1)..@january.end)

    queries = count_queries do
      days.totals(during: @january).by_currency
      days.totals(during: Date.new(2024, 12, 1)..Date.new(2024, 12, 31), kind: :expense).sum
      days.totals(during: @january, currency: "EUR").currencies_by_volume
    end

    assert_equal 1, queries
  end

  private

  def days = Reports::TransactionDays.new(audience_for(@profile))
end
