# frozen_string_literal: true

require "test_helper"

# The database refuses what the models' validations refuse, even from a
# write that skips the model, as update_columns does here.
class CheckConstraintsTest < ActiveSupport::TestCase
  # In a savepoint of its own, so the refused statement doesn't abort the
  # test's transaction for the next one.
  def assert_refused(record, constraint, **values)
    error = assert_raises(ActiveRecord::CheckViolation) do
      ActiveRecord::Base.transaction(requires_new: true) { record.update_columns(values) }
    end
    assert_includes error.message, constraint
  end

  def syringes = Supply.create!(profile: profiles(:alice), name: "Syringe", unit_label: "pcs")

  test "a series, a day and a reminder count positive minutes" do
    reminder = EventReminder.create!(event: events(:groceries), profile: profiles(:alice), offset_minutes: 60)

    assert_refused events(:groceries), "events_duration_minutes_positive", duration_minutes: 0
    assert_refused occurrences(:groceries_due), "occurrences_duration_minutes_positive", duration_minutes: -15
    assert_refused reminder, "event_reminders_offset_minutes_positive", offset_minutes: 0
  end

  test "a book's rating, volume, dates and ISBN" do
    book = books(:dune)

    assert_refused book, "books_rating_range", rating: 6
    assert_refused book, "books_volume_positive", volume: 0
    assert_refused book, "books_finished_after_started",
                   started_on: Date.new(2026, 5, 2), finished_on: Date.new(2026, 5, 1)
    assert_refused book, "books_isbn_format", isbn: "978-0441013"
  end

  test "a pantry never holds less than nothing, and what moves through it is more than nothing" do
    purchase = ingredient_purchase!(profile: profiles(:alice))
    eaten = MealConsumption.create!(occurrence: occurrences(:groceries_due), ingredient: ingredients(:flour),
                                    quantity: 1)

    assert_refused ingredients(:flour), "ingredients_quantity_not_negative", quantity: -1
    assert_refused purchase, "ingredient_purchases_quantity_positive", quantity: 0
    assert_refused recipe_ingredients(:chicken_flour), "recipe_ingredients_quantity_positive", quantity: 0
    assert_refused grocery_list_items(:flour_item), "grocery_list_items_quantity_positive", quantity: -2
    assert_refused eaten, "meal_consumptions_quantity_positive", quantity: 0
  end

  test "a supply is bought, planned and drawn in positive amounts" do
    supply = syringes
    bought = SupplyPurchase.create!(profile: profiles(:alice), supply: supply, purchased_on: Date.current,
                                    quantity_purchased: 10, quantity_remaining: 10)
    planned = SupplyUse.create!(medication_details: medication_details(:methotrexate), supply: supply, quantity: 1)
    drawn = SupplyConsumption.create!(occurrence: occurrences(:methotrexate_taken), supply: supply, quantity: 1)

    assert_refused bought, "supply_purchases_quantity_purchased_positive", quantity_purchased: 0
    assert_refused planned, "supply_uses_quantity_positive", quantity: 0
    assert_refused drawn, "supply_consumptions_quantity_positive", quantity: -1
  end

  test "a reference range has a bound, and its bounds are in order" do
    range = reference_ranges(:glucose_any)

    assert_refused range, "reference_ranges_some_bound", low: nil, high: nil, critical_low: nil, critical_high: nil
    assert_refused range, "reference_ranges_low_below_high", low: 100, high: 100
    assert_refused range, "reference_ranges_critical_low_at_most_low", low: 70, critical_low: 80
    assert_refused range, "reference_ranges_critical_high_at_least_high", high: 100, critical_high: 90
  end

  test "a file's sizes and a link's downloads" do
    link, _token = mint_link(uploads(:lease))

    assert_refused uploads(:lease), "uploads_byte_size_positive", byte_size: 0
    assert_refused uploads(:lease), "uploads_received_bytes_not_negative", received_bytes: -1
    assert_refused link, "upload_links_max_downloads_positive", max_downloads: 0
    assert_refused link, "upload_links_downloads_count_not_negative", downloads_count: -1
  end

  test "a household's currency and slug" do
    assert_refused households(:example), "households_currency_format", currency: "eur"
    assert_refused households(:example), "households_slug_format", slug: "Our Home"
  end

  test "a link is between two people" do
    assert_refused link!(profiles(:alice), profiles(:bob)), "links_two_people", addressee_id: profiles(:alice).id
  end

  test "only a direct conversation has a pair, and only the household's a name" do
    household = Conversation.household_conversation(households(:example))
    direct = Conversation.direct_between(profiles(:alice), profiles(:bob))

    assert_refused household, "conversations_direct_key_on_direct", direct_key: "1:2"
    assert_refused direct, "conversations_direct_key_on_direct", direct_key: nil
    assert_refused direct, "conversations_name_on_household", name: "Us two"
  end

  test "a done day says when it was done, and no other day does" do
    assert_refused occurrences(:groceries_done), "occurrences_completed_at_with_completed", completed_at: nil
    assert_refused occurrences(:groceries_due), "occurrences_completed_at_with_completed", completed_at: Time.current
  end

  test "someone who has joined has a username; an invitation waiting for an answer needs none" do
    assert_refused profiles(:alice), "profiles_username_unless_invited", username: nil
    assert_refused profiles(:alice), "profiles_username_unless_invited", username: " "

    invited = Profile.invite!({ email: "erin@example.com", household: households(:example) }, profiles(:alice)) { _1.skip_invitation = true }
    assert_nil invited.reload.username
  end

  test "a language needs some nouns before it counts" do
    LexiconLanguage.ensure_defaults!

    assert_refused LexiconLanguage.first, "lexicon_languages_min_lemmas_positive", min_lemmas: 0
  end

  test "a payment's amount is more than nothing, and carries no sign" do
    money = events(:electricity_bill).details

    assert_refused money, "transaction_details_amount_cents_positive", amount_cents: 0
    assert_refused money, "transaction_details_amount_cents_positive", amount_cents: -100
  end
end
