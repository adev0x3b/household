# frozen_string_literal: true

require "test_helper"

# What a new record takes from how it was said when the user didn't say it
# outright (each kind's Assistant::DraftBuilder): a medication's kind, a meal
# out, a payment's title.
class Assistant::DraftDefaultsTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
  end

  def create!(type, fields)
    result = submit_changes(assistant_chat(@alice), [ { op: "create", type: type, fields: fields } ], confirm: true)
    assert_equal "saved", result.dig(:data, :status), result.inspect
    Occurrence.find(result.dig(:data, :saved, 0, :id) || Event.find(result.dig(:data, :saved, 0, :event_id)).first_occurrence.tap(&:save!).id)
  end

  test "a medication's kind is read from its name, or from where it is injected" do
    assert_equal "drops", create!("medication", { name: "Vitamin D drops", date: "today" }).event.details.kind
    assert_equal "pill", create!("medication", { name: "Iron tablets", date: "today" }).event.details.kind
    assert_equal "injection", create!("medication", { name: "Ferrous sulphate", date: "today", area: "arm", side: "left" }).event.details.kind
  end

  test "a meal with a price and no recipe was eaten out" do
    meal = create!("meal", { title: "Pizza with Sam", date: "today", amount: "24", payment_method: "card" })
    assert_equal "eating_out", meal.event.details.kind
  end

  test "a payment without a title is named after its notes, else its category and whom it was with" do
    noted = create!("transaction", { date: "today", amount: "12", payment_method: "cash", category: "transport", notes: "parking at the station" })
    assert_equal "parking at the station", noted.event.title

    paid = create!("transaction", { date: "today", amount: "80", payment_method: "cash", category: "home", counterparty: "the plumber" })
    assert_match "the plumber", paid.event.title

    bus = create!("transaction", { date: "today", amount: "2", payment_method: "cash", category: "transportation" })
    assert_equal "Transportation", bus.event.title
  end

  test "a payment with no category has no title to make up, and asks for the category" do
    result = submit_changes(assistant_chat(@alice), [ { op: "create", type: "transaction", fields: { date: "today", amount: "2", payment_method: "cash" } } ])

    assert_equal "needs_input", result.dig(:data, :status), result.inspect
    assert(result.dig(:data, :changes).sole[:missing].any? { |missing| missing.start_with?("transaction.category") })
  end

  test "a collection is a therapy unless it is said to belong elsewhere" do
    submit_changes(assistant_chat(@alice), [ { op: "create", type: "collection", fields: { name: "Physio" } },
                                             { op: "create", type: "collection", fields: { name: "Knee", section: "health" } },
                                             { op: "create", type: "collection", fields: { name: "Larder", section: "pantry" } } ], confirm: true)

    assert_equal({ "Physio" => "healthcare", "Knee" => "healthcare", "Larder" => "pantry" },
                 Collection.where(profile: @alice, name: %w[Physio Knee Larder]).to_h { [ _1.name, _1.section ] })
  end

  test "an ingredient, a recipe or a list is asked for its name before anything else" do
    result = submit_changes(assistant_chat(@alice), [ { op: "create", type: "ingredient", fields: { category: "pantry" } } ])

    assert_equal "needs_input", result.dig(:data, :status), result.inspect
    assert(result.dig(:data, :changes).sole[:missing].any? { |missing| missing.start_with?("ingredient.name") })
  end

  test "something dated in the past happened, its fee paid with it, unless the user says it's still to do" do
    visit = create!("appointment", { title: "Physio", date: "3 days ago", time: "10:00", kind: "medical", counterpart: "Rossi", amount: "50", payment_method: "card" })
    assert_predicate visit, :completed?
    assert_predicate visit.costs.sole, :completed?, "a past visit's fee was paid with it"

    assert_predicate create!("task", { title: "Return the library books", date: "yesterday", status: "pending" }), :pending?
  end

  test "blank lines are left out: a value with no number, a step or ingredient with no words" do
    report = create!("lab_test_result", { date: "today", values: [ { analyte_name: "Glucose", value: "90" }, { analyte_name: "Ferritin", value: " " }, { analyte_name: "", value: "3" } ] })
    assert_equal([ "Glucose" ], report.lab_test_result_entries.map { _1.analyte.name })

    result = submit_changes(assistant_chat(@alice), [ { op: "create", type: "recipe", fields: { name: "Toast", steps: [ "Toast the bread", " " ],
                                                                                                ingredients: [ { ingredient: "Bread", quantity: 2, unit: "pcs" }, { ingredient: " ", quantity: 1 } ] } } ])
    assert_equal "saved", result.dig(:data, :status), result.inspect
    toast = Recipe.find_by!(profile: @alice, name: "Toast")
    assert_equal [ [ "Toast the bread" ], [ "Bread" ] ], [ toast.recipe_steps.map(&:instruction), toast.recipe_ingredients.map { _1.ingredient.name } ]

    dinner = create!("meal", { date: "today", meal_type: "dinner", recipes: [ "Sunday roast chicken", " " ] })
    assert_equal [ "Sunday Roast Chicken" ], Assistant::Resources.meal_recipe_names(dinner)
  end

  test "a dose may use a supply bought in the same call, named as a bare word" do
    result = submit_changes(assistant_chat(@alice), [
                              { op: "create", type: "supply_purchase", fields: { supply: "Lancets", quantity: 100, amount: "9", payment_method: "card" } },
                              { op: "create", type: "medication", fields: { name: "Insulin", date: "today", kind: "injection", area: "arm", side: "left", uses: [ "Lancets", { supply: " " } ] } }
                            ], confirm: true)
    assert_equal "saved", result.dig(:data, :status), result.inspect
    assert_equal([ "Lancets" ], Medication.find_by!(profile: @alice, title: "Insulin").details.supply_uses.map { _1.supply.name })
  end
end
