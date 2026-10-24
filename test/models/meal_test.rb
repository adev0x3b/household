# frozen_string_literal: true

require "test_helper"

class MealTest < ActiveSupport::TestCase
  setup do
    @cook = profiles(:alice)
    @flour = ingredients(:flour)
    @eggs = ingredients(:eggs)
    @pancakes = recipe_with(@cook, "Test pancakes", [ "Flour", 500, "g" ], [ "Eggs", 2, "pcs" ])
    @day = Date.new(2026, 10, 5)
  end

  test "completing a home meal subtracts the recipe ingredients, converting units" do
    meal = meal_on(@cook, @day, recipes: [ @pancakes ])
    meal.complete!

    assert_equal BigDecimal("2.0"), @flour.reload.quantity
    assert_equal 10, @eggs.reload.quantity
    assert_equal 2, meal.meal_consumptions.count
  end

  test "uncompleting gives back exactly what was taken" do
    meal = meal_on(@cook, @day, recipes: [ @pancakes ])
    meal.complete!
    meal.uncomplete!

    assert_equal BigDecimal("2.5"), @flour.reload.quantity
    assert_equal 12, @eggs.reload.quantity
    assert_empty meal.meal_consumptions.reload
  end

  test "short stock never blocks and the real deduction is what gets restored" do
    @eggs.update!(quantity: 1)
    meal = meal_on(@cook, @day, recipes: [ @pancakes ])
    meal.complete!

    assert_equal 0, @eggs.reload.quantity
    assert_equal 1, meal.meal_consumptions.find_by(ingredient: @eggs).quantity

    meal.uncomplete!
    assert_equal 1, @eggs.reload.quantity
  end

  test "completing twice does not deduct twice" do
    meal = meal_on(@cook, @day, recipes: [ @pancakes ])
    meal.complete!
    Meal::Consumption.new(meal).record!

    assert_equal BigDecimal("2.0"), @flour.reload.quantity
  end

  test "ingredients whose units cannot convert are skipped" do
    recipe = recipe_with(@cook, "Pancakes by the gram", [ "Eggs", 100, "g" ])
    meal = meal_on(@cook, @day, recipes: [ recipe ])
    meal.complete!

    assert_equal 12, @eggs.reload.quantity
    assert_empty meal.meal_consumptions
  end

  test "an ingredient missing from the pantry is skipped" do
    recipe = recipe_with(@cook, "Truffle toast", [ "Truffle", 1, "pcs" ])
    meal = meal_on(@cook, @day, recipes: [ recipe ])

    assert_nothing_raised { meal.complete! }
    assert_empty meal.meal_consumptions
  end

  test "eating out never touches the pantry" do
    meal = meal_on(@cook, @day, kind: :eating_out, title: "Da Mario")
    meal.complete!

    assert_equal BigDecimal("2.5"), @flour.reload.quantity
    assert_empty meal.meal_consumptions
  end

  test "resyncing after a recipe edit takes the corrected amount" do
    meal = meal_on(@cook, @day, recipes: [ @pancakes ])
    meal.complete!

    meal.event.details.meal_recipes.destroy_all
    meal.event.details.recipes.reset
    Meal::Consumption.new(meal).resync!

    assert_equal BigDecimal("2.5"), @flour.reload.quantity
    assert_equal 12, @eggs.reload.quantity
  end

  test "destroying a series gives the stock back" do
    meal = meal_on(@cook, @day, recipes: [ @pancakes ])
    meal.complete!
    Occurrences::Destroy.call(meal, by: @cook, scope: "series")

    assert_not Meal.exists?(meal.event_id)
    assert_equal BigDecimal("2.5"), @flour.reload.quantity
    assert_equal 12, @eggs.reload.quantity
  end

  test "a shared recipe draws from the cook's own pantry" do
    cook = profiles(:bob)
    cook_flour = pantry_ingredient(cook, "flour", quantity: 1, unit: "kg")
    meal = meal_on(cook, @day, recipes: [ recipes(:roast_chicken) ])
    meal.complete!

    assert_equal BigDecimal("0.5"), cook_flour.reload.quantity
    assert_equal BigDecimal("2.5"), @flour.reload.quantity, "the recipe owner's shelf is untouched"
  end

  test "a home meal needs a recipe or a name" do
    meal = Meal.new(profile: @cook, starts_on: @day)
    assert_not meal.valid?
    assert_predicate meal.errors[:base], :any?
  end

  test "eating out needs a name" do
    meal = Meal.new(profile: @cook, starts_on: @day, details_attributes: { kind: :eating_out })
    assert_not meal.valid?
    assert_predicate meal.errors[:title], :any?
  end

  test "a recipe the profile cannot see is rejected" do
    meal = meal_on(@cook, @day, kind: :home, title: "Dinner")
    foreign = meal.event.details.meal_recipes.build(recipe: recipes(:pancakes))
    assert_not foreign.valid?
  end

  test "event label falls back to the recipe names" do
    assert_equal "Test pancakes", meal_on(@cook, @day, recipes: [ @pancakes ]).event_label
  end

  test "a projected day of a recurring meal reads the series' recipes, so one-tap completion deducts" do
    template = meal_on(@cook, @day, recipes: [ @pancakes ], rrule: "FREQ=WEEKLY")

    next_week = template.event.occurrence_on(@day + 7)
    next_week.complete!

    assert_equal [ @pancakes.id ], next_week.details.resolved_recipes.pluck(:id)
    assert_equal BigDecimal("2.0"), @flour.reload.quantity
  end

  test "a day with its own recipes is named after them and cooks them" do
    toast = recipe_with(@cook, "Toast", [ "Eggs", 1, "pcs" ])
    template = meal_on(@cook, @day, recipes: [ @pancakes ], rrule: "FREQ=WEEKLY")

    next_week = template.event.occurrence_on(@day + 7)
    next_week.write_details!(meal_recipes_attributes: [ { recipe_id: toast.id } ])
    assert_equal "Toast", next_week.event_label
    assert_equal "Test pancakes", template.event_label

    next_week.complete!
    assert_equal 11, @eggs.reload.quantity
    assert_equal BigDecimal("2.5"), @flour.reload.quantity
  end

  test "a meal out is paid to the place it is named after" do
    dinner = Meal.new(profile: @cook, title: "Trattoria da Mario", starts_on: Date.current, details_attributes: { kind: :eating_out })
    day = dinner.first_occurrence

    assert_equal "Trattoria da Mario", dinner.cost_counterpart(day)
    assert_equal I18n.t("meals.form.transaction_title", title: "Trattoria da Mario", date: I18n.l(day.date, format: :long)), dinner.cost_title(day)
  end

  test "is due at the meal's usual hour" do
    dinner = meal_on(@cook, @day, kind: :eating_out, title: "Da Mario", meal_type: :dinner)
    assert_equal [ [ 19, 30 ], false ], dinner.event.due_clock(dinner)
  end

  test "a planned home meal is short when the pantry can't cover it, and no longer once it is eaten" do
    @eggs.update!(quantity: 1)
    meal = meal_on(@cook, @day, recipes: [ @pancakes ])
    out = meal_on(@cook, @day, kind: :eating_out, title: "Da Mario")

    assert meal.event.short_on?(meal)
    assert_not out.event.short_on?(out)

    meal.complete!
    assert_not meal.event.short_on?(meal)
  end
end
