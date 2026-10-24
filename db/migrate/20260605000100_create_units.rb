# frozen_string_literal: true

class CreateUnits < ActiveRecord::Migration[8.1]
  def change
    create_table :units do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :units, "LOWER(name)", unique: true, name: "index_units_on_lower_name"
  end
end
