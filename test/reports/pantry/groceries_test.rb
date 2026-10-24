# frozen_string_literal: true

require "test_helper"

class Reports::Pantry::GroceriesTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2025, 3, 15)
  end

  test "items to buy are the unchecked items of active lists" do
    list = GroceryList.create!(profile: @profile, name: "Weekly")
    list.grocery_list_items.create!(ingredient_name: "Milk", quantity: 1)
    list.grocery_list_items.create!(ingredient_name: "Rice", quantity: 1, checked: true)
    done = GroceryList.create!(profile: @profile, name: "Done", status: :completed)
    done.grocery_list_items.create!(ingredient_name: "Salt", quantity: 1)

    assert_equal 1, report.open_items_metric.value
    assert_equal([ [ "Weekly", 2, 1 ] ], report.list_rows.map { |row| [ row.list.name, row.total, row.checked ] })
  end

  test "grocery spend is completed grocery expenses, never summed across currencies" do
    expense!(profile: @profile, date: @today - 2, cents: 5000, category: :groceries)
    expense!(profile: @profile, date: @today - 3, cents: 900, category: :groceries, status: :pending)
    expense!(profile: @profile, date: @today - 4, cents: 700, category: :housing)
    expense!(profile: @profile, date: @today - 5, cents: 2000, category: :groceries, currency: "USD")
    expense!(profile: @profile, date: @today - 40, cents: 1000, category: :groceries)

    metric = report.spend_metric

    assert_equal [ "EUR", 5000 ], [ metric.value.currency, metric.value.cents ]
    assert_equal 1000, metric.previous.cents
    assert_equal([ [ "USD", 2000 ] ], report.other_currencies.map { |money| [ money.currency, money.cents ] })
  end

  test "a day's own category decides whether it was groceries" do
    weekly = series!("Transaction", profile: @profile, starts_on: @today - 13, rrule: "FREQ=WEEKLY", title: "Market",
                                    kind: :expense, category: :groceries, amount: "30")
    day!(weekly, date: @today - 13, status: :completed)
    day!(weekly, date: @today - 6, status: :completed).write_details!(category: :dining_out)

    assert_equal 3000, report.spend_metric.value.cents
  end

  test "a grocery expense shared with several people is counted once" do
    transaction = expense!(profile: @profile, date: @today - 2, cents: 5000, category: :groceries)
    EventShare.create!(event: transaction.event, profile: profiles(:alice))
    EventShare.create!(event: transaction.event, profile: profiles(:bob))

    assert_equal 5000, report.spend_metric.value.cents
  end

  test "groceries over the period: spend per bucket and what was bought most often" do
    expense!(profile: @profile, date: @today - 2, cents: 5000, category: :groceries)
    expense!(profile: @profile, date: @today - 2, cents: 1000, category: :groceries)
    ingredient_purchase!(profile: @profile, name: "Flour", quantity: 1, purchased_on: @today - 3)
    ingredient_purchase!(profile: @profile, name: "Flour", quantity: 2, purchased_on: @today - 10)
    ingredient_purchase!(profile: @profile, name: "Rice", quantity: 1, purchased_on: @today - 4)
    ingredient_purchase!(profile: @profile, name: "Rice", quantity: 5, purchased_on: @today - 60)
    ingredient_purchase!(profile: profiles(:alice), name: "Salt", quantity: 1, purchased_on: @today - 3)

    assert_predicate report, :any?
    assert_in_delta(60.0, report.spend_chart.series.first.values.sum)
    assert_equal "EUR", report.spend_chart.currency
    assert_equal([ [ "Flour", 2, 3, "kg" ], [ "Rice", 1, 1, "kg" ] ], report.purchase_rows.map { |row| [ row.name, row.times, row.quantity.to_i, row.unit ] })
  end

  test "with nothing in the period there is nothing to show" do
    assert_not report.any?
  end

  private

  def report = dashboard.groceries

  def dashboard
    Reports::Pantry::Dashboard.new(audience: audience_for(@profile), period: Reports::Period.recent(today: @today), today: @today)
  end
end
