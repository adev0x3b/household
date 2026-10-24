# frozen_string_literal: true

require "test_helper"

# validates_accessible: a record never points at someone else's records,
# whichever way the id arrives (a form, the assistant's output).
class AccessibleReferencesTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob) # collections(:b12), Alice's, is shared with Bob
    @carol = profiles(:carol)
  end

  test "a series can join the owner's collection or one shared with them, nobody else's" do
    assert_predicate Task.new(profile: @alice, starts_on: Date.current, title: "x", collection: collections(:b12)), :valid?
    assert_predicate Task.new(profile: @bob, starts_on: Date.current, title: "x", collection: collections(:b12)), :valid?

    event = Task.new(profile: @carol, starts_on: Date.current, title: "x", collection: collections(:b12))
    assert_not event.valid?
    assert_includes event.errors[:collection], "isn't one you have access to"
  end

  test "revoking a share later doesn't invalidate what already points at it" do
    event = Task.create!(profile: @bob, starts_on: Date.current, title: "x", collection: collections(:b12))
    collection_shares(:b12_bob).destroy!

    event.reload.update!(starts_on: Date.current + 1)
    carols = Collection.create!(profile: @carol, name: "Physio", section: "healthcare")
    assert_not event.update(collection: carols) # still checked when it changes
  end

  test "a cost can't be about someone else's day" do
    carols = appointment!(profile: @carol, date: Date.current)

    error = assert_raises(ActiveRecord::RecordInvalid) { expense!(profile: @alice, date: Date.current, cents: 100, about: carols) }
    assert_match "isn't one you have access to", error.message
    assert_predicate expense!(profile: @carol, date: Date.current, cents: 100, about: carols), :persisted?
  end

  test "purchases use the buyer's own supplies and ingredients" do
    carols_supply = supply_purchase!(profile: @carol, name: "Saline").supply

    assert_not SupplyPurchase.new(supply: carols_supply, profile: @alice, quantity_purchased: 1, purchased_on: Date.current).valid?
    assert_not IngredientPurchase.new(ingredient: ingredients(:olive_oil), profile: @alice, quantity: 1, purchased_on: Date.current).valid?
  end

  test "a dose only plans and uses supplies its owner can access" do
    dose = medication!(profile: @carol, date: Date.current)
    alices = supply_purchase!(profile: @alice, name: "Needles").supply

    use = SupplyUse.new(medication_details: dose.event.details, supply: alices, quantity: 1)
    assert_not use.valid?
    assert_includes use.errors[:supply], "isn't one you have access to"

    consumption = SupplyConsumption.new(occurrence: dose, supply: alices, quantity: 1)
    assert_not consumption.valid?
    assert_includes consumption.errors[:supply], "isn't one you have access to"
  end

  test "records checked together ask once per kind of target and owner, and each takes its own answer" do
    dose = medication!(profile: @carol, date: Date.current)
    carols = %w[Needles Swabs Vials].map { supply_purchase!(profile: @carol, name: _1).supply }
    alices = supply_purchase!(profile: @alice, name: "Plasters").supply
    uses = [ *carols, alices ].map { SupplyUse.new(medication_details: dose.event.details, supply_id: _1.id, quantity: 1) }

    assert_queries_match(/FROM "supplies"/, count: 2) { SupplyUse.read_access(uses) } # the targets, then the question
    assert_no_queries_match(/FROM "supplies"/) do
      assert_equal [ true, true, true, false ], uses.map(&:valid?)
    end
    assert_includes uses.last.errors[:supply], "isn't one you have access to"

    # A target changed since is asked again.
    uses.first.supply = alices
    assert_not uses.first.valid?
  end

  test "a meal is only cooked from recipes its owner can see, checked together when it has several" do
    meal = meal_on(@carol, Date.current, title: "Supper")
    details = meal.event.details
    carols = Recipe.create!(profile: @carol, name: "Soup")

    assert_predicate MealRecipe.new(meal_details: details, recipe: carols), :valid?
    alices = MealRecipe.new(meal_details: details, recipe: recipes(:roast_chicken))
    assert_not alices.valid?
    assert_includes alices.errors[:recipe], "isn't one you have access to"

    assert_raises(ActiveRecord::RecordInvalid) { details.replace_recipes!([ carols.id, recipes(:roast_chicken).id ]) }
    assert_empty details.meal_recipes.reload, "nothing is kept of a refused list"
    details.replace_recipes!([ carols.id ])
    assert_equal [ carols ], details.recipes.reload
  end

  test "lab values only name the result owner's analytes" do
    day = LabTestResult.create!(profile: @carol, starts_on: Date.current, title: "Bloods").occurrence_on(Date.current)

    assert_not LabTestResultEntry.new(occurrence: day, analyte: analytes(:glucose), value: "90").valid?
  end
end
