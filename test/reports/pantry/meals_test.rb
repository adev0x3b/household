# frozen_string_literal: true

require "test_helper"

class Reports::Pantry::MealsTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2025, 3, 15)
  end

  test "meals planned are today's and the next 7 days' meals not eaten yet" do
    meal_on(@profile, @today, title: "Soup")
    meal_on(@profile, @today + 7, title: "Stew")
    meal_on(@profile, @today + 1, title: "Eaten early", status: :completed)
    meal_on(@profile, @today + 8, title: "Too far")
    meal_on(@profile, @today - 1, title: "Yesterday")

    assert_equal 2, report.planned_metric.value
  end

  test "meals as planned is eaten over due in the last 30 days" do
    meal_on(@profile, @today - 2, title: "Soup", status: :completed)
    meal_on(@profile, @today - 3, title: "Stew")
    meal_on(@profile, @today - 4, title: "Out", status: :cancelled)

    assert_in_delta(50.0, report.eaten_metric.value)
  end

  test "a planned home meal the cook's pantry can't cover is listed with what's short" do
    pantry_ingredient(@profile, "Flour", quantity: 0.2)
    pantry_ingredient(@profile, "Eggs", quantity: 12, unit: "pc")
    bread = recipe_with(@profile, "Bread", [ "Flour", 1, "kg" ], [ "Eggs", 2, "pc" ])
    omelette = recipe_with(@profile, "Omelette", [ "Eggs", 3, "pc" ])
    meal_on(@profile, @today + 1, recipes: [ bread ])
    meal_on(@profile, @today + 2, recipes: [ omelette ])

    rows = report.short_rows

    assert_equal([ [ @today + 1, [ "Flour" ], "Bread" ] ], rows.map { |row| [ row.date, row.missing, row.title ] })
  end

  test "a repeating meal's planned days cook its series' recipes, or a day's own" do
    pantry_ingredient(@profile, "Flour", quantity: 0.2)
    pantry_ingredient(@profile, "Eggs", quantity: 12, unit: "pc")
    bread = recipe_with(@profile, "Bread", [ "Flour", 1, "kg" ])
    omelette = recipe_with(@profile, "Omelette", [ "Eggs", 3, "pc" ])
    meal_on(@profile, @today - 6, recipes: [ bread ], rrule: "FREQ=WEEKLY") # next on today + 1, nothing stored
    daily = meal_on(@profile, @today, recipes: [ omelette ], rrule: "FREQ=DAILY").event
    day = daily.occurrence_on(@today + 2)
    day.materialize!
    row = day.override_details
    row.meal_recipes.build(recipe: bread)
    day.adopt_override_details!(row)

    rows = report.short_rows

    assert_equal([ [ @today + 1, "Bread", true ], [ @today + 2, "Bread", false ] ], rows.map { |r| [ r.date, r.title, r.occurrence.projected? ] })
  end

  test "meals over the period: outcomes per bucket and completion by kind of meal" do
    meal_on(@profile, @today - 2, title: "Soup", meal_type: :lunch, status: :completed)
    meal_on(@profile, @today - 3, title: "Stew", meal_type: :lunch)
    meal_on(@profile, @today - 4, title: "Eggs", meal_type: :breakfast, status: :completed)
    meal_on(@profile, @today - 5, title: "Out", meal_type: :dinner, status: :cancelled)
    meal_on(@profile, @today, title: "Tonight", meal_type: :dinner)

    chart = report.outcomes_chart

    assert_predicate report, :any?
    assert_equal %w[good critical series-1], chart.series.map(&:color)
    assert_equal([ 2, 1, 1 ], chart.series.map { |series| series.values.sum })
    assert_equal([ [ "breakfast", 1, 1, 100.0 ], [ "lunch", 2, 1, 50.0 ] ], report.meal_type_rows.map { |row| row.to_h.values })
  end

  test "a day's own kind of meal wins over its series'" do
    series = meal_on(@profile, @today - 3, title: "Leftovers", meal_type: :lunch, rrule: "FREQ=DAILY").event
    day!(series, date: @today - 2, status: :completed).write_details!(meal_type: :dinner)
    day!(series, date: @today - 1, status: :completed)

    assert_equal([ [ "lunch", 2, 1 ], [ "dinner", 1, 1 ] ], report.meal_type_rows.map { |row| [ row.meal_type, row.due, row.eaten ] })
  end

  test "with nothing in the period there is nothing to show" do
    assert_not report.any?
  end

  private

  def report = dashboard.meals

  def dashboard
    Reports::Pantry::Dashboard.new(audience: audience_for(@profile), period: Reports::Period.recent(today: @today), today: @today)
  end
end
