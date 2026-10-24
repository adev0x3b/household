# frozen_string_literal: true

class CreateGroceryListItems < ActiveRecord::Migration[8.1]
  def change
    create_table :grocery_list_items do |t|
      t.references :grocery_list, null: false, foreign_key: true
      t.references :ingredient, null: false, foreign_key: true
      t.decimal :quantity, precision: 10, scale: 3, null: false
      t.references :unit, null: true, foreign_key: true
      t.boolean :checked, null: false, default: false
      t.datetime :checked_at

      t.timestamps

      t.index [ :grocery_list_id, :ingredient_id ], unique: true
    end
  end
end
