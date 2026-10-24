# frozen_string_literal: true

# Who saved each record more than one person can edit, so a refused save
# can say who changed it meanwhile. Empty on every existing row, and
# whenever a save didn't say who, or that person was removed. The indexes
# are built without blocking writes, and the keys are checked by the next
# migration.
class AddUpdatedByToWhatHousematesEditTogether < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TABLES = %i[events occurrences recipes collections grocery_lists grocery_list_items supply_purchases conversations].freeze

  def change
    TABLES.each do |table|
      add_reference table, :updated_by, index: { algorithm: :concurrently, name: "index_#{table}_on_updated_by_id" },
                                        foreign_key: { to_table: :profiles, on_delete: :nullify, validate: false },
                                        if_not_exists: true
    end
  end
end
