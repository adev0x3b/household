# frozen_string_literal: true

require "test_helper"

# Undo (Assistant::ChangeSets::Undoer): each kind of step a change set logs
# goes back as it was, newest first; what was changed or removed since is
# left alone, and what can't be undone says so.
class Assistant::UndoTest < ActiveSupport::TestCase
  Undoer = Assistant::ChangeSets::Undoer

  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    @chat = assistant_chat(@alice)
  end

  # Submits operations as the tools do, applying what waits for the button.
  def change!(*operations)
    data = Assistant::ChangeSets::Submit.call(chat: @chat, operations: operations, confirm: true)
    assert_includes %w[saved waiting_for_user], data[:status].to_s, data.inspect
    Assistant::ChangeSet.find(data[:change_set_id]).tap do |set|
      Assistant::ChangeSets::Applier.call(set, confirmed: true) unless set.applied?
      @chat = assistant_chat(@alice)
    end
  end

  def undo(set) = Undoer.call(set.reload)

  test "only an applied change can be undone, and a step nothing undoes says so" do
    set = Assistant::ChangeSet.current_for(@chat)
    assert_equal :not_applied, assert_raises(Undoer::CannotUndo) { Undoer.call(set) }.key

    set.update!(status: :applied, applied_at: Time.current, undo_log: [ { "kind" => "merged" } ])
    assert_equal :deleted, assert_raises(Undoer::CannotUndo) { Undoer.call(set) }.key
  end

  test "a share and an unshare go back; a share removed meanwhile is left as it is" do
    recipe = Recipe.create!(profile: @alice, name: "Pesto")
    shared = change!({ op: "share", type: "recipe", ref: recipe.id, fields: { with: @bob.first_name } })
    assert recipe.recipe_shares.exists?(profile: @bob)
    undo(shared)
    assert_not recipe.recipe_shares.exists?(profile: @bob)

    Shares::Create.call(recipe, with: @bob, by: @alice)
    unshared = change!({ op: "unshare", type: "recipe", ref: recipe.id, fields: { with: @bob.first_name } })
    assert_not recipe.recipe_shares.exists?(profile: @bob)
    undo(unshared)
    assert recipe.recipe_shares.exists?(profile: @bob)

    again = change!({ op: "share", type: "recipe", ref: recipe.id, fields: { with: profiles(:carol).first_name } })
    recipe.recipe_shares.find_by!(profile: profiles(:carol)).destroy!
    assert undo(again)
    assert_predicate again.reload, :undone?
  end

  test "a grocery list's items, and their ticks, go back as they were" do
    list = GroceryList.create!(profile: @alice, name: "Week")
    flour = list.grocery_list_items.create!(ingredient: ingredients(:flour), quantity: 1, unit: units(:kg))
    eggs = list.grocery_list_items.create!(ingredient: ingredients(:eggs), quantity: 6, unit: units(:pcs))
    eggs.check!
    stock = -> { [ ingredients(:flour), ingredients(:eggs) ].map { _1.reload.quantity } }
    before = stock.call

    ticked = change!({ op: "update", type: "grocery_list", ref: list.id, fields: { check_items: [ "Flour" ], uncheck_items: [ "Eggs" ] } })
    assert_predicate flour.reload, :checked?
    assert_not eggs.reload.checked?
    undo(ticked)
    assert_not flour.reload.checked?
    assert_predicate eggs.reload, :checked?
    assert_equal before, stock.call, "the shelf as it was"

    changed = change!({ op: "update", type: "grocery_list", ref: list.id, fields: { items: [ { ingredient: "Milk", quantity: 2, unit: "l" } ], remove_items: [ "Flour" ] } })
    assert_equal %w[Eggs Milk], list.grocery_list_items.reload.map { _1.ingredient.name }.sort
    undo(changed)
    assert_equal %w[Eggs Flour], list.grocery_list_items.reload.map { _1.ingredient.name }.sort
  end

  test "a range goes back with the analyte and unit it added, and values that took its unit give it back" do
    report = lab_result!(profile: @alice, date: Date.new(2026, 9, 16), values: { "Ferritin" => "40" })
    set = change!({ op: "set_range", fields: { analyte: "Ferritin", unit: "ng/mL", low: 30, high: 400 } })
    entry = report.lab_test_result_entries.sole
    assert_equal "ng/mL", entry.reload.unit&.name, "a value without a unit takes the range's"

    assert_difference [ "ReferenceRange.count", "Unit.count" ], -1 do
      undo(set)
    end
    assert_nil entry.reload.unit
    assert Analyte.exists?(name: "Ferritin", profile: @alice), "its values still name it"

    fresh = change!({ op: "set_range", fields: { analyte: "Transferrin", unit: "mg/dL", low: 200, high: 360 } })
    assert_difference "Analyte.count", -1 do
      undo(fresh)
    end
  end

  test "the doses done at once go back to upcoming, the days they saved unsaved" do
    AssistantEval::Seeds.b12_injection_series(@alice)
    series = Medication.find_by!(profile: @alice, title: "Cobalamin injection")
    saved_before = series.occurrences.pluck(:id)
    result = run_tool(:mark_done, @chat, type: "medication", all: true, query: "cobalamin", date_from: "2026-09-01", date_to: "2026-09-24")
    assert_equal "saved", result[:data][:status], result.inspect
    assert_empty series.occurrences.where.not(status: :completed), "every day it saved is done"
    assert_predicate series.occurrences.completed, :many?

    undo(Assistant::ChangeSet.find(result[:data][:change_set_id]))
    assert_equal saved_before, series.occurrences.reload.pluck(:id), "the days only the set saved are upcoming again"
    assert series.occurrences.all?(&:pending?)
  end

  test "what was created goes, but a supply bought before stays" do
    task = change!({ op: "create", type: "task", fields: { title: "Repot the basil", date: "tomorrow" } })
    undo(task)
    assert_not Task.exists?(title: "Repot the basil")

    needles = supply_purchase!(profile: @alice, name: "Needles").supply
    bought = change!({ op: "create", type: "supply_purchase", fields: { supply: "Needles", quantity: 100, amount: "12", payment_method: "card" } })
    undo(bought)
    assert Supply.exists?(needles.id), "it was bought before"
    assert_equal 1, needles.supply_purchases.count
  end

  test "a renamed recipe gets its name back" do
    pesto = Recipe.create!(profile: @alice, name: "Pesto")
    renamed = change!({ op: "update", type: "recipe", ref: pesto.id, fields: { name: "Basil pesto" } })
    assert_equal "Basil pesto", pesto.reload.name
    undo(renamed)
    assert_equal "Pesto", pesto.reload.name
  end

  test "a lab report's values go back as they were, and a change that leaves them alone leaves their rows alone" do
    report = lab_result!(profile: @alice, date: Date.new(2026, 9, 16), values: { "Ferritin" => "40" })
    entry = report.lab_test_result_entries.sole

    fixed = change!({ op: "update", type: "lab_test_result", ref: report.id, fields: { values: { "Ferritin" => "45" } } })
    assert_equal "45", entry.reload.value
    undo(fixed)
    assert_equal [ "40" ], report.lab_test_result_entries.reload.map(&:value)

    kept = report.lab_test_result_entries.sole
    noted = change!({ op: "update", type: "lab_test_result", ref: report.id, fields: { notes: "fasting" } })
    undo(noted)
    assert_equal [ kept.id ], report.lab_test_result_entries.reload.ids, "its values were never touched"
  end

  test "a range's new unit stays once something else uses it, and a range deleted meanwhile stays gone" do
    set = change!({ op: "set_range", fields: { analyte: "Glucose", unit: "mmol/L", low: 3.9, high: 5.5 } })
    unit = Unit.find_by!(name: "mmol/L", household: @alice.household)
    lab_result!(profile: @alice, date: Date.new(2026, 10, 1)).lab_test_result_entries.create!(analyte: analytes(:glucose), unit: unit, value: "5")
    ReferenceRange.find_by!(analyte: analytes(:glucose), unit: unit).destroy!

    assert undo(set)
    assert Unit.exists?(unit.id), "a value uses it"
  end

  test "a range's new unit stays once the pantry uses it, and goes with the range when nothing does" do
    { ingredient: "tbsp", purchase: "jar" }.each do |use, name|
      set = change!({ op: "set_range", fields: { analyte: "Glucose", unit: name, low: 3.9, high: 5.5 } })
      unit = Unit.find_by!(name: name, household: @alice.household)
      if use == :ingredient
        Ingredient.create!(profile: @alice, name: "Honey", quantity: 1, unit: unit)
      else
        ingredient_purchase!(profile: @alice, name: "Jam", unit: nil).update!(unit: unit)
      end

      assert undo(set), use
      assert Unit.exists?(unit.id), "the #{use} uses it"
    end

    set = change!({ op: "set_range", fields: { analyte: "Glucose", unit: "mmol/L", low: 3.9, high: 5.5 } })
    assert undo(set)
    assert_not Unit.exists?(name: "mmol/L", household: @alice.household)
  end

  test "an analyte a range added stays once a value names it" do
    set = change!({ op: "set_range", fields: { analyte: "Transferrin", unit: "mg/dL", low: 200, high: 360 } })
    transferrin = Analyte.find_by!(name: "Transferrin", profile: @alice)
    lab_result!(profile: @alice, date: Date.new(2026, 10, 1)).lab_test_result_entries.create!(analyte: transferrin, value: "250")

    assert undo(set)
    assert Analyte.exists?(transferrin.id)
    assert_empty transferrin.reference_ranges
  end

  test "a supply a purchase added stays once it is bought again" do
    bought = change!({ op: "create", type: "supply_purchase", fields: { supply: "Lancets", quantity: 100, amount: "9", payment_method: "card" } })
    lancets = Supply.find_by!(profile: @alice, name: "Lancets")
    SupplyPurchase.create!(supply: lancets, profile: @alice, quantity_purchased: 50, quantity_remaining: 50, purchased_on: Date.current)

    assert undo(bought)
    assert_equal [ 50 ], lancets.supply_purchases.reload.map(&:quantity_purchased)
  end

  test "an upcoming day marked not done is unsaved again on undo" do
    laundry = series!(Task, profile: @alice, starts_on: Date.current, rrule: "FREQ=DAILY", title: "Laundry")
    tomorrow = Date.current + 1
    set = change!({ op: "uncomplete", type: "task", ref: "event_id #{laundry.id} on #{tomorrow.iso8601}" })
    assert laundry.occurrences.exists?(date: tomorrow)

    undo(set)
    assert_not laundry.occurrences.exists?(date: tomorrow)
  end
end
