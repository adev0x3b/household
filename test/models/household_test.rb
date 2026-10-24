# frozen_string_literal: true

require "test_helper"

class HouseholdTest < ActiveSupport::TestCase
  test "the slug comes from the name unless given, and is unique" do
    household = Household.create!(name: "Casa Rossi")
    assert_equal "casa-rossi", household.slug

    again = Household.new(name: "Casa Rossi")
    assert_not again.valid?
    assert again.errors.of_kind?(:slug, :taken)
  end

  test "a profile needs a household, and its housemates are the others in it" do
    assert_not Profile.new(username: "nobody", email: "nobody@example.com", password: "secret-password").valid?

    assert_equal [ profiles(:bob), profiles(:carol) ].sort_by(&:id), profiles(:alice).housemates.order(:id).to_a
    assert_empty profiles(:outsider).housemates
  end

  test "nothing is shared with someone of another household" do
    event = events(:groceries)
    recipe = Recipe.create!(profile: profiles(:alice), name: "Soup")
    list = GroceryList.create!(profile: profiles(:alice), name: "Week")
    collection = Collection.create!(profile: profiles(:alice), name: "B12", section: "healthcare")

    [ EventShare.new(event: event, profile: profiles(:outsider)),
      RecipeShare.new(recipe: recipe, profile: profiles(:outsider)),
      GroceryListShare.new(grocery_list: list, profile: profiles(:outsider)),
      CollectionShare.new(collection: collection, profile: profiles(:outsider)) ].each do |share|
      assert_not share.valid?, share.class.name
      assert share.errors.of_kind?(:profile, :outside_household), share.class.name
    end

    assert_predicate RecipeShare.new(recipe: recipe, profile: profiles(:bob)), :valid?
  end

  test "a transaction's other side is a housemate" do
    transaction = Transaction.new(profile: profiles(:alice), starts_on: Date.current, title: "Rent share",
                                  details_attributes: { kind: :expense, category: :housing, amount: 100, currency: "EUR",
                                                        payment_method: :bank_transfer, counterparty_profile: profiles(:outsider) })

    assert_not transaction.valid?
    assert transaction.details.errors.of_kind?(:counterparty_profile, :outside_household)

    transaction.details.counterparty_profile = profiles(:bob)
    assert_predicate transaction, :valid?
  end

  test "a quantity can't be in another household's unit" do
    theirs = Unit.create!(household: households(:elsewhere), name: "sacks")
    ingredient = Ingredient.new(profile: profiles(:alice), name: "Rice", unit: theirs)

    assert_not ingredient.valid?
    assert ingredient.errors.of_kind?(:unit, :outside_household)
  end

  test "the assistant only knows the profile's housemates" do
    members = Assistant::Members.new(profiles(:alice))

    assert_not_includes members.all, profiles(:outsider)
    assert_nil members.resolve("Dave").profile
  end

  test "a household counts its money in its own currency: a payment's when none is said, an empty report's" do
    household = households(:example)
    assert_equal "EUR", household.currency
    household.update!(currency: "CHF")
    assert_not household.update(currency: "francs")

    alice = profiles(:alice).reload
    visit = appointment!(profile: alice, date: Date.new(2026, 10, 6))
    cost = Transactions::SetCost.call(visit, date: Date.new(2026, 10, 6), title: "Visit", amount: "50", payment_method: "card").cost
    assert_equal "CHF", cost.details.currency

    assert_equal "CHF", Reports::Audience.new(viewer: alice).currency
  end
end
