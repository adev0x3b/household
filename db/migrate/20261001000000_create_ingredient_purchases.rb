# frozen_string_literal: true

class CreateIngredientPurchases < ActiveRecord::Migration[8.1]
  def change
    create_table :ingredient_purchases do |t|
      t.references :ingredient, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.decimal :quantity, precision: 10, scale: 3, null: false
      t.references :unit, null: true, foreign_key: true
      t.date :purchased_on, null: false
      t.references :grocery_list_item, null: true, foreign_key: { on_delete: :nullify }

      t.timestamps

      t.index [ :ingredient_id, :purchased_on ]
    end
  end
end
