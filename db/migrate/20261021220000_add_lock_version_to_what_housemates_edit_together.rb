# frozen_string_literal: true

# A version on each record more than one person can edit, which Rails
# checks and moves on with every update, so a form saved after someone
# else's save is refused rather than undoing it. The constant default is
# written into the catalog, not into each row, so the existing rows read 0
# at once without the table being rewritten or locked, and the version
# still serving, which sends no version, saves as before.
class AddLockVersionToWhatHousematesEditTogether < ActiveRecord::Migration[8.1]
  TABLES = %i[events occurrences recipes collections grocery_lists grocery_list_items supply_purchases conversations].freeze

  def change
    TABLES.each { |table| add_column table, :lock_version, :integer, default: 0, null: false }
  end
end
