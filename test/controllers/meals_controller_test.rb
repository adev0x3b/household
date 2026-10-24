# frozen_string_literal: true

require "test_helper"

class MealsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @cook = profiles(:alice)
    sign_in @cook
    @flour = ingredients(:flour)
    @recipe = recipe_with(@cook, "Test bread", [ "Flour", 500, "g" ])
    @day = Date.new(2026, 10, 6)
  end

  def recipes_key = "meal[details_attributes][meal_recipes_attributes]"

  test "new renders the form modal with a recipe picker" do
    get new_meal_path(date: @day.iso8601), as: :turbo_stream

    assert_response :success
    assert_includes response.body, "Test bread"
    assert_select "select[name='meal[details_attributes][kind]']"
    assert_select "template select[name='#{recipes_key}[NEW_RECORD][recipe_id]']"
  end

  test "creating a home meal with a recipe" do
    assert_difference -> { Meal.count } => 1, -> { MealRecipe.count } => 1, -> { Transaction.count } => 0 do
      post meals_path, as: :turbo_stream, params: {
        meal: { date: @day.iso8601, details_attributes: { kind: "home", meal_type: "dinner", meal_recipes_attributes: { "-1" => { recipe_id: @recipe.id } } } }
      }
    end

    assert_response :success
    meal = Meal.order(:id).last
    assert_equal [ @recipe ], meal.details.recipes.to_a
    assert_equal "Test bread", meal.event_label
    assert_equal BigDecimal("2.5"), @flour.reload.quantity, "planning a meal leaves the pantry alone"
  end

  test "a home meal with neither a recipe nor a name re-renders the form" do
    assert_no_difference "Meal.count" do
      post meals_path, as: :turbo_stream, params: { meal: { date: @day.iso8601, details_attributes: { kind: "home" } } }
    end

    assert_response :unprocessable_content
    assert_includes response.body, "turbo-stream"
    assert_includes response.body, "Add at least one recipe or a name for the meal"
  end

  test "eating out records a dining_out expense with the payment method" do
    assert_difference -> { Meal.count } => 1, -> { Transaction.count } => 1 do
      post meals_path, as: :turbo_stream, params: {
        meal: { title: "Da Mario", date: @day.iso8601, details_attributes: { kind: "eating_out", meal_type: "dinner" } },
        transaction: { amount: "42.50", payment_method: "card" }
      }
    end

    cost = Meal.order(:id).last.first_occurrence.costs.sole
    assert_equal "dining_out", cost.details.category
    assert_equal "card", cost.details.payment_method
    assert_equal BigDecimal("42.5"), cost.details.amount
    assert_predicate cost, :pending?, "a cost entered in the form isn't paid until the user says so"
  end

  test "eating a meal takes the ingredients, once however often it is pressed, and not eating it gives them back" do
    meal = meal_on(@cook, @day, recipes: [ @recipe ])

    post event_day_completion_path(meal.event, meal.date), as: :turbo_stream
    assert_response :success
    assert_equal BigDecimal("2.0"), @flour.reload.quantity

    post event_day_completion_path(meal.event, meal.date), as: :turbo_stream
    assert_predicate meal.reload, :completed?
    assert_equal BigDecimal("2.0"), @flour.reload.quantity, "a second press asks for what already holds"

    delete event_day_completion_path(meal.event, meal.date), as: :turbo_stream
    assert_equal BigDecimal("2.5"), @flour.reload.quantity
  end

  test "eating a day nothing was stored about saves it and deducts stock" do
    meal = meal_on(@cook, @day, recipes: [ @recipe ], rrule: "FREQ=WEEKLY")

    assert_difference "Occurrence.count", 1 do
      post event_day_completion_path(meal.event, @day + 7), as: :turbo_stream
    end

    assert_predicate meal.event.occurrence_on(@day + 7), :completed?
    assert_equal BigDecimal("2.0"), @flour.reload.quantity
  end

  test "cancelling a completed meal in the form gives the ingredients back" do
    meal = meal_on(@cook, @day, recipes: [ @recipe ])
    meal.complete!

    patch event_day_path(meal.event, meal.date), as: :turbo_stream, params: { meal: { status: "cancelled", details_attributes: { kind: "home" } } }

    assert_equal "cancelled", meal.reload.status
    assert_equal BigDecimal("2.5"), @flour.reload.quantity
  end

  # Every request is watched for N+1 queries (test_helper.rb).
  test "eating a meal of many ingredients takes each from the pantry, and not eating it returns them" do
    shelf = [ @flour, ingredients(:eggs), pantry_ingredient(@cook, "Sugar", quantity: 1), pantry_ingredient(@cook, "Milk", quantity: 2, unit: "l") ]
    crepes = recipe_with(@cook, "Crêpes", [ "Flour", 200, "g" ], [ "Eggs", 2, "pcs" ], [ "Sugar", 100, "g" ], [ "Milk", 500, "ml" ])
    meal = meal_on(@cook, @day, recipes: [ crepes ])

    post event_day_completion_path(meal.event, meal.date), as: :turbo_stream
    assert_equal(%w[2.3 10.0 0.9 1.5].map { BigDecimal(_1) }, shelf.map { _1.reload.quantity })

    delete event_day_completion_path(meal.event, meal.date), as: :turbo_stream
    assert_equal(%w[2.5 12.0 1.0 2.0].map { BigDecimal(_1) }, shelf.map { _1.reload.quantity })
  end

  test "swapping the recipe of a completed meal corrects the pantry" do
    meal = meal_on(@cook, @day, recipes: [ @recipe ])
    meal.complete!
    bigger = recipe_with(@cook, "Big bread", [ "Flour", 1, "kg" ])
    current = meal.details.meal_recipes.sole

    get edit_event_day_path(meal.event, meal.date), as: :turbo_stream
    assert_select "input[type=hidden][name='#{recipes_key}[#{current.id}][id]'][value=?]", current.id.to_s

    patch event_day_path(meal.event, meal.date), as: :turbo_stream, params: {
      meal: { status: "completed", details_attributes: { kind: "home", meal_recipes_attributes: {
        current.id.to_s => { id: current.id, _destroy: "1" },
        "-1" => { recipe_id: bigger.id }
      } } }
    }

    assert_equal [ bigger ], meal.event.details.reload.recipes.to_a
    assert_equal BigDecimal("1.5"), @flour.reload.quantity
  end

  test "a day of a weekly meal gets recipes of its own, or the whole series new ones" do
    meal = meal_on(@cook, @day, recipes: [ @recipe ], rrule: "FREQ=WEEKLY")
    series_recipe = meal.event.details.meal_recipes.sole
    soup = recipe_with(@cook, "Soup", [ "Flour", 10, "g" ])

    get edit_event_day_path(meal.event, meal.date), as: :turbo_stream
    assert_select "form[data-controller~=apply-to]"
    assert_select "input[name='#{recipes_key}[#{series_recipe.id}][id]'][data-apply-to-scope=series][disabled]"

    patch event_day_path(meal.event, meal.date), as: :turbo_stream, params: {
      meal: { apply_to: "day", details_attributes: { kind: "home", meal_recipes_attributes: { series_recipe.id.to_s => { recipe_id: soup.id } } } }
    }
    assert_equal [ soup ], meal.reload.own_details.recipes.to_a
    assert_equal [ @recipe ], meal.event.details.reload.recipes.to_a, "the other days keep the series' bread"
    assert_equal [ @recipe ], meal.event.occurrence_on(@day + 7).details.resolved_recipes.to_a

    patch event_day_path(meal.event, @day + 7), as: :turbo_stream, params: {
      meal: { apply_to: "series", details_attributes: { kind: "home", meal_recipes_attributes: {
        series_recipe.id.to_s => { id: series_recipe.id, recipe_id: soup.id }
      } } }
    }
    assert_equal [ soup ], meal.event.details.reload.recipes.to_a
  end

  test "a profile the meal is not shared with cannot mark it eaten" do
    meal = meal_on(@cook, @day, recipes: [ @recipe ])
    sign_in profiles(:carol)

    post event_day_completion_path(meal.event, meal.date), as: :turbo_stream

    assert_not meal.reload.completed?
    assert_equal BigDecimal("2.5"), @flour.reload.quantity
  end
end
