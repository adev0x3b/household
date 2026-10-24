# frozen_string_literal: true

# Checks the keys the previous migration added, each without blocking
# writes. Every row there is empty or was written by the new version, which
# names only people who exist, so none can stop the deploy.
class ValidateUpdatedByOfWhatHousematesEditTogether < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TABLES = %i[events occurrences recipes collections grocery_lists grocery_list_items supply_purchases conversations].freeze

  def change
    TABLES.each { |table| validate_foreign_key table, :profiles, column: :updated_by_id }
  end
end
