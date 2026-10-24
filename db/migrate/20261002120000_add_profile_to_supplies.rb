# frozen_string_literal: true

# Supplies stop being one catalog shared by every profile: each belongs to the
# profile that bought it, with names unique per profile (like ingredients).
#
# Existing rows: a supply goes to the profile of its earliest purchase. A
# supply other profiles bought too is copied once per extra profile, and their
# purchases and consumptions move to their copy. A supply nobody bought goes
# to the first admin (else the first profile).
class AddProfileToSupplies < ActiveRecord::Migration[8.1]
  def up
    add_reference :supplies, :profile, foreign_key: true, null: true
    # Before splitting: a profile's copy shares its name with the original.
    remove_index :supplies, name: "index_supplies_on_lower_name"

    split_existing_supplies if select_value("SELECT COUNT(*) FROM supplies").to_i.positive?

    change_column_null :supplies, :profile_id, false
    add_index :supplies, "profile_id, lower((name)::text)", unique: true, name: "index_supplies_on_profile_id_and_lower_name"
  end

  def down
    remove_index :supplies, name: "index_supplies_on_profile_id_and_lower_name"
    add_index :supplies, "lower((name)::text)", unique: true, name: "index_supplies_on_lower_name"
    remove_reference :supplies, :profile, foreign_key: true
  end

  private

  def split_existing_supplies
    fallback = select_value("SELECT id FROM profiles ORDER BY (role = 1) DESC, id LIMIT 1")
    raise "supplies exist but there is no profile to give them to" unless fallback

    select_rows("SELECT id FROM supplies ORDER BY id").each do |(supply_id)|
      buyers = select_values(<<~SQL)
        SELECT profile_id FROM supply_purchases WHERE supply_id = #{supply_id}
        GROUP BY profile_id ORDER BY MIN(purchased_on), MIN(id)
      SQL
      owner, *others = buyers.presence || [ fallback ]
      execute "UPDATE supplies SET profile_id = #{owner} WHERE id = #{supply_id}"
      others.each { |profile_id| move_to_copy(supply_id, profile_id) }
    end
  end

  def move_to_copy(supply_id, profile_id)
    copy_id = select_value(<<~SQL)
      INSERT INTO supplies (name, category, unit_label, low_stock_threshold, pao_days, profile_id, created_at, updated_at)
      SELECT name, category, unit_label, low_stock_threshold, pao_days, #{profile_id}, created_at, NOW()
      FROM supplies WHERE id = #{supply_id}
      RETURNING id
    SQL
    purchases = "SELECT id FROM supply_purchases WHERE supply_id = #{supply_id} AND profile_id = #{profile_id}"

    # Consumptions follow the batch they drew from; those without one follow
    # whoever took the dose.
    execute <<~SQL
      UPDATE supply_consumptions SET supply_id = #{copy_id}
      WHERE supply_id = #{supply_id} AND (
        supply_purchase_id IN (#{purchases})
        OR (supply_purchase_id IS NULL AND medication_id IN (
          SELECT medications.id FROM medications JOIN events ON events.id = medications.event_id
          WHERE events.profile_id = #{profile_id}))
      )
    SQL
    execute "UPDATE supply_purchases SET supply_id = #{copy_id} WHERE id IN (#{purchases})"
  end
end
