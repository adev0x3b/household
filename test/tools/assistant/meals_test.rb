# frozen_string_literal: true

require "test_helper"

class Assistant::MealsTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @chat = assistant_chat(@alice)
    travel_to Time.zone.local(2026, 9, 22, 12)
    @pantry = pantry_ingredient(@alice, "Semolina", quantity: 1, unit: "kg")
    @recipe = recipe_with(@alice, "Gnocchi", [ "Semolina", 300, "g" ])
  end

  teardown { travel_back }

  def meals = days_of(Meal, @alice)
  def recipes_of(meal) = Assistant::Resources.meal_recipe_names(meal.persisted? ? meal.reload : meal)

  test "plan_meals saves one meal per entry with its recipes" do
    other = recipe_with(@alice, "Polenta", [ "Semolina", 100, "g" ])

    result = run_tool(:plan_meals, @chat, meals: [
                        { date: "2026-09-23", meal_type: "dinner", recipes: [ "Gnocchi" ] },
                        { date: "2026-09-24", meal_type: "dinner", recipes: [ "polenta" ] }
                      ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal([ [ "Gnocchi" ], [ "Polenta" ] ], meals.map { |m| recipes_of(m) })
    assert(meals.all? { |m| m.details.home? })
    assert meals.all?(&:pending?)
    assert_equal [ other ], meals.last.details.resolved_recipes.to_a
  end

  test "a dish named in the title of a home meal is read as that recipe" do
    result = run_tool(:plan_meals, @chat, meals: [ { date: "2026-09-23", meal_type: "dinner", kind: "home", title: "gnocchi" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    meal = meals.sole
    assert_equal [ @recipe ], meal.details.resolved_recipes.to_a
    assert_nil meal.event.title
  end

  test "an unknown recipe is never created: it asks, listing the user's recipes" do
    result = run_tool(:plan_meals, @chat, meals: [ { date: "2026-09-23", meal_type: "dinner", recipes: [ "Moon pie" ] } ])

    assert_equal "needs_input", result[:data][:status], result.inspect
    assert(result[:data][:changes].sole[:missing].any? { |m| m.start_with?("meal.recipes") })
    assert_match "Gnocchi", result.to_json
    assert_nil Recipe.find_by(profile: @alice, name: "Moon pie")
    assert_equal 0, Meal.where(profile: @alice).count
  end

  test "an unknown recipe from someone with no recipes yet says only that it isn't there" do
    result = run_tool(:plan_meals, assistant_chat(AssistantEval::Sandbox.profile!), meals: [ { date: "2026-09-23", meal_type: "dinner", recipes: [ "Moon pie" ] } ])

    problem = result[:data][:changes].sole[:missing].find { |m| m.start_with?("meal.recipes") }
    assert_match 'no recipe named "Moon pie".', problem
    assert_no_match "the user's recipes", problem
  end

  test "a meal out saves its cost as a dining_out expense, with no recipes" do
    result = run_tool(:plan_meals, @chat, meals: [
                        { date: "2026-09-21", meal_type: "dinner", kind: "eating_out", title: "Trattoria Roma", amount: 45, payment_method: "card" }
                      ])

    assert_equal "saved", result[:data][:status], result.inspect
    meal = meals.sole
    assert_equal [ "Trattoria Roma", "eating_out" ], [ meal.title, meal.details.kind ]
    assert_predicate meal, :completed?, "a past meal is saved as done"
    transaction = meal.costs.sole
    assert_equal "dining_out", transaction.details.category
    assert_equal 45, amount_of(transaction)
    assert_equal "card", paid_with(transaction)
    assert_predicate transaction, :completed?
    assert_equal 1, @pantry.reload.quantity, "eating out never touches the pantry"
  end

  test "a meal out with a price but no payment method asks for it" do
    result = run_tool(:plan_meals, @chat, meals: [
                        { date: "2026-09-23", meal_type: "dinner", kind: "ordered_in", title: "Pizza", amount: 24 }
                      ])

    assert_equal "needs_input", result[:data][:status], result.inspect
    assert_nil Meal.find_by(title: "Pizza")
    assert_empty meals
  end

  test "a cost on a home meal is ignored and the model is told" do
    result = run_tool(:plan_meals, @chat, meals: [
                        { date: "2026-09-23", meal_type: "dinner", recipes: [ "Gnocchi" ], amount: 12, payment_method: "card" }
                      ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_empty meals.sole.costs
  end

  test "mark_done on a cooked meal takes its ingredients out, and undo gives them back" do
    run_tool(:plan_meals, @chat, meals: [ { date: "2026-09-22", meal_type: "lunch", recipes: [ "Gnocchi" ] } ])
    meal = meals.sole

    result = run_tool(:mark_done, @chat, type: "meal", ref: meal.id.to_s)
    assert_equal "saved", result[:data][:status], result.inspect
    assert_in_delta 0.7, @pantry.reload.quantity, 0.0001

    Assistant::ChangeSets::Undoer.call(@chat.change_sets.last)
    assert_in_delta 1, @pantry.reload.quantity, 0.0001
    assert_predicate meal.reload, :pending?
  end

  test "a past planned meal is saved as done and deducts stock" do
    run_tool(:plan_meals, @chat, meals: [ { date: "2026-09-20", meal_type: "dinner", recipes: [ "Gnocchi" ] } ])

    assert_in_delta 0.7, @pantry.reload.quantity, 0.0001
  end

  test "update_record swaps a meal's recipes, and undo puts them back" do
    run_tool(:plan_meals, @chat, meals: [ { date: "2026-09-23", meal_type: "dinner", recipes: [ "Gnocchi" ] } ])
    meal = meals.sole
    recipe_with(@alice, "Polenta", [ "Semolina", 100, "g" ])

    result = run_tool(:update_record, @chat, type: "meal", ref: meal.id.to_s, recipes: [ "Polenta" ], remove_recipes: [ "Gnocchi" ])
    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ "Polenta" ], recipes_of(meal)

    Assistant::ChangeSets::Undoer.call(@chat.change_sets.last)
    assert_equal [ "Gnocchi" ], recipes_of(meal)
  end

  test "editing a completed meal's recipes reconciles the pantry" do
    meal = meal_on(@alice, Date.new(2026, 9, 22), recipes: [ @recipe ])
    meal.complete!
    assert_in_delta 0.7, @pantry.reload.quantity, 0.0001
    polenta = recipe_with(@alice, "Polenta", [ "Semolina", 100, "g" ])

    run_tool(:update_record, @chat, type: "meal", ref: meal.id.to_s, recipes: [ "Polenta" ], remove_recipes: [ "Gnocchi" ])
    assert_in_delta 0.9, @pantry.reload.quantity, 0.0001

    Assistant::ChangeSets::Undoer.call(@chat.change_sets.last)
    assert_in_delta 0.7, @pantry.reload.quantity, 0.0001
    assert_equal [ "Gnocchi" ], recipes_of(meal)
    assert_predicate polenta, :persisted?
  end

  test "a day of a weekly meal changes its own recipes; the other days keep the series'" do
    meal = meal_on(@alice, Date.new(2026, 9, 16), recipes: [ @recipe ], rrule: "FREQ=WEEKLY")
    recipe_with(@alice, "Polenta", [ "Semolina", 100, "g" ])

    result = run_tool(:update_record, @chat, type: "meal", ref: "event_id #{meal.event_id} on 2026-09-23", recipes: [ "Polenta" ])
    assert_equal "saved", result[:data][:status], result.inspect
    day = meal.event.occurrences.find_by!(date: Date.new(2026, 9, 23))
    assert_equal [ "Gnocchi", "Polenta" ], recipes_of(day).sort
    assert_equal [ "Gnocchi" ], recipes_of(meal.event.occurrence_on(Date.new(2026, 9, 30)))

    Assistant::ChangeSets::Undoer.call(@chat.change_sets.last)
    assert_not Occurrence.exists?(day.id), "the day it saved goes back to upcoming"
    assert_equal [ "Gnocchi" ], recipes_of(meal.event.occurrence_on(Date.new(2026, 9, 23)))
  end

  test "search_records finds a meal by its recipe name and recipes report what the pantry is short of" do
    meal_on(@alice, Date.new(2026, 9, 25), recipes: [ @recipe ])
    @pantry.update!(quantity: 0.1)

    found = run_tool(:search_records, @chat, type: "meal", query: "gnocchi")
    assert_equal 1, found[:data][:count], found.inspect

    recipe = run_tool(:get_record, @chat, type: "recipe", id: @recipe.id)
    assert_match "Semolina", recipe[:data][:short_in_pantry].to_s
  end
end
