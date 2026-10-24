# frozen_string_literal: true

require "test_helper"

# The pantry's tools: ingredients, recipes and grocery lists. Names here
# avoid the ones alice's fixtures already have (Flour, Eggs, Weekly shop):
# the fixtures load for every test, and a name reused would trip the
# assistant's own duplicate-name check.
class Assistant::PantryToolsTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @carol = profiles(:carol)
    @chat = assistant_chat(@alice)
    travel_to Time.zone.local(2026, 9, 22, 12)
  end

  teardown { travel_back }

  test "add_ingredient saves a new ingredient with its quantity and unit" do
    result = run_tool(:add_ingredient, @chat, name: "Cinnamon", quantity: 2, unit: "kg")

    assert_equal "saved", result[:data][:status], result.inspect
    ingredient = Ingredient.find_by!(profile: @alice, name: "Cinnamon")
    assert_equal 2, ingredient.quantity.to_i
    assert_equal "kg", ingredient.unit.name
  end

  test "add_ingredient with a name already in the pantry is refused, pointing at update_record" do
    existing = Ingredient.create!(profile: @alice, name: "Cinnamon", quantity: 1)

    result = run_tool(:add_ingredient, @chat, name: "Cinnamon", quantity: 1)

    assert_not result[:ok]
    assert_match "update_record with ref #{existing.id}", result[:error]
    assert_equal 1, Ingredient.where(profile: @alice, name: "Cinnamon").count
  end

  test "record_groceries adds to the stock of an existing ingredient, converting the unit" do
    flour = ingredients(:flour)

    result = run_tool(:record_groceries, @chat, items: [ { ingredient: "flour", quantity: 500, unit: "g" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal 3, flour.reload.quantity
    purchase = flour.ingredient_purchases.sole
    assert_in_delta(0.5, purchase.quantity)
    assert_equal "kg", purchase.unit.name
    assert_empty purchase.costs
  end

  test "record_groceries with a price and payment saves a groceries expense, and undo gives everything back" do
    flour = ingredients(:flour)

    result = run_tool(:record_groceries, @chat, items: [ { ingredient: "Flour", quantity: 1, unit: "kg", amount: 2.5 } ],
                                                payment_method: "card", shop: "Lidl")

    assert_equal "saved", result[:data][:status], result.inspect
    txn = flour.ingredient_purchases.sole.costs.sole
    assert_predicate txn.details, :groceries?
    assert_equal "card", paid_with(txn)
    assert_equal "Lidl", txn.details.counterparty
    assert_in_delta(3.5, flour.reload.quantity)

    Assistant::ChangeSets::Undoer.call(@chat.change_sets.last)

    assert_in_delta(2.5, flour.reload.quantity)
    assert_equal 0, flour.ingredient_purchases.count
    assert_not Event.exists?(txn.event_id)
  end

  test "record_groceries asks for the payment when only a price was given" do
    result = run_tool(:record_groceries, @chat, items: [ { ingredient: "Flour", quantity: 1, unit: "kg", amount: 2.5 } ])

    assert_equal "needs_input", result[:data][:status], result.inspect
    assert_match "payment_method", result[:data].to_json
    assert_equal 0, ingredients(:flour).ingredient_purchases.count
  end

  test "record_groceries asks for the quantity when it wasn't said" do
    result = run_tool(:record_groceries, @chat, items: [ { ingredient: "Flour" } ])

    assert_equal "needs_input", result[:data][:status], result.inspect
    assert_match "quantity", result[:data].to_json
  end

  test "record_groceries creates a new ingredient kept in the unit it was bought in" do
    result = run_tool(:record_groceries, @chat, items: [ { ingredient: "Cinnamon", quantity: 2, unit: "kg" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    ingredient = Ingredient.find_by!(profile: @alice, name: "Cinnamon")
    assert_equal 2, ingredient.quantity
    assert_equal "kg", ingredient.unit.name
    assert_equal 1, ingredient.ingredient_purchases.count
  end

  test "record_groceries doesn't put milk into Oat milk" do
    oat = Ingredient.create!(profile: @alice, name: "Oat milk", quantity: 1, unit_name: "l")

    result = run_tool(:record_groceries, @chat, items: [ { ingredient: "milk", quantity: 1, unit: "l" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal 1, oat.reload.quantity
    assert_equal 1, Ingredient.find_by!(profile: @alice, name: "milk").quantity
  end

  test "record_groceries refuses a unit that can't be converted" do
    result = run_tool(:record_groceries, @chat, items: [ { ingredient: "Flour", quantity: 3, unit: "pcs" } ])

    assert_not_equal "saved", result.dig(:data, :status), result.inspect
    assert_in_delta(2.5, ingredients(:flour).reload.quantity)
    assert_equal 0, ingredients(:flour).ingredient_purchases.count
  end

  test "record_groceries saves several items in one call" do
    result = run_tool(:record_groceries, @chat, items: [ { ingredient: "Flour", quantity: 1, unit: "kg" },
                                                         { ingredient: "Eggs", quantity: 6, unit: "pcs" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_in_delta(3.5, ingredients(:flour).reload.quantity)
    assert_equal 18, ingredients(:eggs).reload.quantity
  end

  test "add_ingredient for a name in the pantry points at record_groceries for a purchase" do
    result = run_tool(:add_ingredient, @chat, name: "Flour", quantity: 1)

    assert_not result[:ok]
    assert_match "record_groceries", result[:error]
  end

  test "checking off a grocery item whose unit can't convert is refused up front" do
    run_tool(:add_grocery_list, @chat, name: "Party supplies", items: [ { ingredient: "Flour", quantity: 3, unit: "pcs" } ])

    result = run_tool(:update_record, @chat, type: "grocery_list", ref: "Party supplies", check_items: [ "Flour" ])

    assert_not_equal "saved", result.dig(:data, :status), result.inspect
    assert_in_delta(2.5, ingredients(:flour).reload.quantity)
  end

  test "add_recipe saves its steps in order and its ingredients, adding a new one as needed" do
    Ingredient.create!(profile: @alice, name: "Cinnamon", quantity: 1)

    result = run_tool(:add_recipe, @chat, name: "Waffles",
                                          steps: [ { instruction: "Mix" }, { instruction: "Cook" } ],
                                          ingredients: [ { ingredient: "cinnamon", quantity: 2, unit: "cups" }, { ingredient: "Vanilla extract", quantity: 1 } ])

    assert_equal "saved", result[:data][:status], result.inspect
    recipe = Recipe.find_by!(profile: @alice, name: "Waffles")
    assert_equal [ "Mix", "Cook" ], recipe.recipe_steps.order(:position).pluck(:instruction)
    assert_equal [ "Cinnamon", "Vanilla extract" ], recipe.recipe_ingredients.includes(:ingredient).map { |ri| ri.ingredient.name }.sort
    assert_equal 1, Ingredient.where(profile: @alice, name: "Cinnamon").count, "matched the existing ingredient, not a duplicate"
  end

  test "add_recipe without any step asks for one" do
    result = run_tool(:add_recipe, @chat, name: "Mystery dish")

    assert_equal "needs_input", result[:data][:status]
    assert_includes result[:data][:changes].sole[:missing], "recipe.steps"
  end

  test "add_grocery_list saves its items, matching an existing ingredient by name" do
    Ingredient.create!(profile: @alice, name: "Oat milk", quantity: 1)

    result = run_tool(:add_grocery_list, @chat, name: "Party supplies",
                                                items: [ { ingredient: "oat milk", quantity: 2 }, { ingredient: "Baking soda", quantity: 1 } ])

    assert_equal "saved", result[:data][:status], result.inspect
    list = GroceryList.find_by!(profile: @alice, name: "Party supplies")
    assert_equal [ "Baking soda", "Oat milk" ], list.grocery_list_items.includes(:ingredient).map { |i| i.ingredient.name }.sort
    assert_equal 1, Ingredient.where(profile: @alice, name: "Oat milk").count
  end

  test "add_grocery_list saves items named without a quantity" do
    result = run_tool(:add_grocery_list, @chat, name: "Party supplies", items: [ { ingredient: "Baking soda" }, { ingredient: "Oat milk", quantity: 2 } ])

    assert_equal "saved", result[:data][:status], result.inspect
    list = GroceryList.find_by!(profile: @alice, name: "Party supplies")
    assert_equal({ "Baking soda" => nil, "Oat milk" => 2 }, list.grocery_list_items.includes(:ingredient).to_h { |i| [ i.ingredient.name, i.quantity&.to_i ] })

    checked = run_tool(:update_record, @chat, type: "grocery_list", ref: "Party supplies", check_items: [ "Baking soda" ])

    assert_equal "saved", checked[:data][:status], checked.inspect
    assert_predicate list.grocery_list_items.joins(:ingredient).find_by!(ingredients: { name: "Baking soda" }), :checked?
  end

  test "checking a grocery item off restocks its ingredient, and undo gives the stock back" do
    run_tool(:add_grocery_list, @chat, name: "Party supplies", items: [ { ingredient: "Baking soda", quantity: 6 } ])
    ingredient = Ingredient.find_by!(profile: @alice, name: "Baking soda")
    starting = ingredient.quantity

    result = run_tool(:update_record, @chat, type: "grocery_list", ref: "Party supplies", check_items: [ "baking soda" ])

    assert_equal "saved", result[:data][:status], result.inspect
    item = GroceryListItem.joins(:ingredient).find_by!(ingredients: { id: ingredient.id })
    assert_predicate item, :checked?
    assert_equal starting + 6, ingredient.reload.quantity

    Assistant::ChangeSets::Undoer.call(@chat.change_sets.last)

    assert_not item.reload.checked?
    assert_equal starting, ingredient.reload.quantity
  end

  test "update_record adds and removes grocery list items" do
    run_tool(:add_grocery_list, @chat, name: "Party supplies", items: [ { ingredient: "Baking soda", quantity: 6 } ])

    result = run_tool(:update_record, @chat, type: "grocery_list", ref: "Party supplies",
                                             items: [ { ingredient: "Oat milk", quantity: 1 } ], remove_items: [ "Baking soda" ])

    assert_equal "saved", result[:data][:status], result.inspect
    list = GroceryList.find_by!(profile: @alice, name: "Party supplies")
    assert_equal([ "Oat milk" ], list.grocery_list_items.includes(:ingredient).map { |i| i.ingredient.name })
  end

  test "update_record fixes an item's quantity, and passes over an item with no name and names not on the list" do
    run_tool(:add_grocery_list, @chat, name: "Party supplies", items: [ { ingredient: "Baking soda", quantity: 6 } ])

    result = run_tool(:update_record, @chat, type: "grocery_list", ref: "Party supplies",
                                             items: [ { ingredient: "baking soda", quantity: 2 }, { quantity: 3 } ],
                                             remove_items: [ "Vanilla" ], check_items: [ "Saffron" ])

    assert_equal "saved", result[:data][:status], result.inspect
    list = GroceryList.find_by!(profile: @alice, name: "Party supplies")
    assert_equal({ "Baking soda" => [ 2, false ] }, list.grocery_list_items.includes(:ingredient).to_h { |i| [ i.ingredient.name, [ i.quantity.to_i, i.checked ] ] })
  end

  test "update_record changes a plain ingredient field" do
    Ingredient.create!(profile: @alice, name: "Baking soda", quantity: 1)

    result = run_tool(:update_record, @chat, type: "ingredient", ref: "Baking soda", changes: { quantity: 5 })

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal 5, Ingredient.find_by!(profile: @alice, name: "Baking soda").quantity.to_i
  end

  test "deleting an ingredient waits for the button" do
    Ingredient.create!(profile: @alice, name: "Baking soda", quantity: 1)

    result = run_tool(:delete_records, @chat, type: "ingredient", ref: "Baking soda")

    assert_equal "waiting_for_user", result[:data][:status]
    assert Ingredient.exists?(profile: @alice, name: "Baking soda")
  end

  test "sharing a recipe with a household member waits for the button, then the Apply button saves it" do
    run_tool(:add_recipe, @chat, name: "Waffles", steps: [ { instruction: "Cook" } ])

    result = run_tool(:share, @chat, type: "recipe", ref: "Waffles", with: @carol.first_name)
    assert_equal "waiting_for_user", result[:data][:status]

    Assistant::ChangeSets::Applier.call(@chat.change_sets.last, confirmed: true)
    recipe = Recipe.find_by!(profile: @alice, name: "Waffles")
    assert_includes recipe.shared_profiles, @carol
  end

  test "search_records and get_record see ingredients, recipes and grocery lists" do
    run_tool(:add_ingredient, @chat, name: "Cinnamon", quantity: 1)
    run_tool(:add_recipe, @chat, name: "Waffles", steps: [ { instruction: "Cook" } ])
    run_tool(:add_grocery_list, @chat, name: "Party supplies")

    assert_equal 1, run_tool(:search_records, @chat, type: "ingredient", query: "cinnamon")[:data][:count]
    recipe = Recipe.find_by!(profile: @alice, name: "Waffles")
    assert_equal "Waffles", run_tool(:get_record, @chat, type: "recipe", id: recipe.id)[:data][:name]
    assert_equal 1, run_tool(:search_records, @chat, type: "grocery_list", query: "party")[:data][:count]
  end
end
