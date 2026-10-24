# frozen_string_literal: true

# Who runs a household: its first member, who can remove the others. Set
# when a household is created (Households::Create); existing households get
# their oldest profile.
class AddOwnerToHouseholds < ActiveRecord::Migration[8.1]
  def up
    add_reference :households, :owner, foreign_key: { to_table: :profiles, on_delete: :nullify }
    execute(<<~SQL.squish)
      UPDATE households SET owner_id = (
        SELECT id FROM profiles WHERE profiles.household_id = households.id ORDER BY created_at, id LIMIT 1
      )
    SQL
  end

  def down
    remove_reference :households, :owner
  end
end
