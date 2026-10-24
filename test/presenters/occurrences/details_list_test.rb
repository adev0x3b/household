# frozen_string_literal: true

require "test_helper"

# A list on a kind's details as a day's form shows it: which rows, and the
# hidden ids that let the save go to the day or to the whole series.
class Occurrences::DetailsListTest < ActiveSupport::TestCase
  PREFIX = ->(index) { "meal[recipes][#{index}]" }

  setup do
    @cook = profiles(:alice)
    @bread = recipe_with(@cook, "Bread", [ "Flour", 500, "g" ])
    @soup = recipe_with(@cook, "Soup", [ "Flour", 10, "g" ])
    @day = Date.new(2026, 10, 6)
  end

  test "a one-off meal's rows are its series', named by their ids alone" do
    meal = meal_on(@cook, @day, recipes: [ @bread ])
    list = list_of(meal)
    series_recipe = meal.event.details.meal_recipes.sole

    assert_equal [ series_recipe ], list.rows.map(&:child)
    assert_equal [ { type: "hidden", name: "meal[recipes][#{series_recipe.id}][id]", value: series_recipe.id } ],
                 list.id_inputs(list.rows.sole)
    assert_empty list.dropped_inputs
  end

  test "a day of a repeating meal still on the series' rows names each for the series only" do
    meal = meal_on(@cook, @day, recipes: [ @bread ], rrule: "FREQ=WEEKLY")
    inputs = list_of(meal).then { |list| list.id_inputs(list.rows.sole) }

    assert_equal([ { apply_to_scope: "series", apply_to_held: "1" } ], inputs.pluck(:data))
    assert(inputs.all? { _1[:disabled] })
  end

  test "a day with rows of its own names each on both lists, and the series drops the rest" do
    meal = meal_on(@cook, @day, recipes: [ @bread, @soup ], rrule: "FREQ=WEEKLY")
    series_bread, series_soup = meal.event.details.meal_recipes.sort_by { _1.recipe.name }
    meal.write_details!(kind: "home")
    own_bread = meal.own_details.meal_recipes.create!(recipe: @bread)

    list = list_of(meal.reload)
    row = list.rows.sole

    assert_equal [ own_bread.id, series_bread.id ], [ row.day_id, row.series_id ]
    assert_equal(%w[day series], list.id_inputs(row).map { _1[:data][:apply_to_scope] })
    assert_equal [ "meal[recipes][#{series_soup.id}][id]", "meal[recipes][#{series_soup.id}][_destroy]" ],
                 list.dropped_inputs.pluck(:name)
  end

  test "a row not saved yet is indexed by a negative number, as strong parameters only takes numbers" do
    meal = Meal.new(profile: @cook, starts_on: @day)
    meal.details.meal_recipes.build(recipe: @bread)

    row = list_of(meal.occurrence_on(@day)).rows.sole
    assert_predicate row.index, :negative?
    assert_nil row.series_id
  end

  private

  def list_of(day) = Occurrences::DetailsList.new(day, :meal_recipes, key: :recipe_id, prefix: PREFIX)
end
