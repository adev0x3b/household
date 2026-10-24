# frozen_string_literal: true

class CreateAnalytes < ActiveRecord::Migration[8.1]
  def change
    create_table :analytes do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :analytes, "LOWER(name)", unique: true, name: "index_analytes_on_lower_name"
  end
end
