# frozen_string_literal: true

class CreateIngredients < ActiveRecord::Migration[8.1]
  def change
    create_table :ingredients do |t|
      t.references :profile, null: false, foreign_key: true
      t.string :name, null: false
      t.decimal :quantity, precision: 10, scale: 3, null: false, default: 0
      t.references :unit, null: true, foreign_key: true

      t.timestamps
    end

    add_index :ingredients, "profile_id, LOWER(name)", unique: true, name: "index_ingredients_on_profile_id_and_lower_name"
  end
end
