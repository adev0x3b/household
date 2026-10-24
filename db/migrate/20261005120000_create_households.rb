# frozen_string_literal: true

# Every profile belongs to a household, and nothing crosses from one
# household to another: a profile's records are its own, shares stay between
# housemates, and the unit vocabulary is the household's. What already
# exists becomes the "zemal" household.
class CreateHouseholds < ActiveRecord::Migration[8.1]
  def up
    create_table :households do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
      t.index :slug, unique: true
    end

    add_reference :profiles, :household, foreign_key: true
    add_reference :units, :household, foreign_key: true

    if select_value("SELECT 1 FROM profiles LIMIT 1") || select_value("SELECT 1 FROM units LIMIT 1")
      household_id = select_value(<<~SQL.squish)
        INSERT INTO households (name, slug, created_at, updated_at)
        VALUES ('zemal', 'zemal', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id
      SQL
      execute("UPDATE profiles SET household_id = #{household_id.to_i}")
      execute("UPDATE units SET household_id = #{household_id.to_i}")
    end

    change_column_null :profiles, :household_id, false
    change_column_null :units, :household_id, false

    remove_index :units, name: "index_units_on_lower_name"
    add_index :units, "household_id, lower((name)::text)", unique: true, name: "index_units_on_household_id_and_lower_name"
  end

  def down
    remove_index :units, name: "index_units_on_household_id_and_lower_name"
    add_index :units, "lower((name)::text)", unique: true, name: "index_units_on_lower_name"
    remove_reference :units, :household, foreign_key: true
    remove_reference :profiles, :household, foreign_key: true
    drop_table :households
  end
end
