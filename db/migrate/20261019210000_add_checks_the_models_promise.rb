# frozen_string_literal: true

# A value's own rules, which the models validate, held by the database as
# well: a bulk update, a migration or a console session can't leave a row
# the app would refuse. Each one mirrors a validation as written. Lists the
# app grows with its features (an enum's values, the sections, a language's
# roles) stay the models' alone, so adding a value never needs a migration.
#
# Added without checking the rows there are, which would hold a lock on the
# table while the version still serving writes to it; the next migration
# checks them.
class AddChecksTheModelsPromise < ActiveRecord::Migration[8.1]
  def change
    positive :events, :duration_minutes
    positive :occurrences, :duration_minutes
    positive :event_reminders, :offset_minutes

    check :books, "rating BETWEEN 1 AND 5", name: "books_rating_range"
    check :books, "volume >= 1", name: "books_volume_positive"
    check :books, "finished_on >= started_on", name: "books_finished_after_started"
    check :books, "isbn ~ '^[0-9]{13}$'", name: "books_isbn_format"

    check :ingredients, "quantity >= 0", name: "ingredients_quantity_not_negative"
    positive :ingredient_purchases, :quantity
    positive :recipe_ingredients, :quantity
    positive :grocery_list_items, :quantity
    positive :meal_consumptions, :quantity
    positive :supply_purchases, :quantity_purchased
    positive :supply_consumptions, :quantity
    positive :supply_uses, :quantity

    check :reference_ranges, "num_nonnulls(low, high, critical_low, critical_high) > 0",
          name: "reference_ranges_some_bound"
    check :reference_ranges, "low < high", name: "reference_ranges_low_below_high"
    check :reference_ranges, "critical_low <= low", name: "reference_ranges_critical_low_at_most_low"
    check :reference_ranges, "critical_high >= high", name: "reference_ranges_critical_high_at_least_high"

    positive :uploads, :byte_size
    check :uploads, "received_bytes >= 0", name: "uploads_received_bytes_not_negative"
    positive :upload_links, :max_downloads
    check :upload_links, "downloads_count >= 0", name: "upload_links_downloads_count_not_negative"

    check :households, "currency ~ '^[A-Z]{3}$'", name: "households_currency_format"
    check :households, "slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'", name: "households_slug_format"

    check :links, "requester_id <> addressee_id", name: "links_two_people"
    check :conversations, "(kind = 0) = (direct_key IS NOT NULL)", name: "conversations_direct_key_on_direct"
    check :conversations, "name IS NULL OR kind = 1", name: "conversations_name_on_household"

    positive :lexicon_languages, :min_lemmas
  end

  private

  # A row whose value is NULL passes a CHECK, so an optional column needs
  # no "IS NULL OR".
  def check(table, expression, name:)
    add_check_constraint table, expression, name: name, validate: false
  end

  def positive(table, column)
    check table, "#{column} > 0", name: "#{table}_#{column}_positive"
  end
end
