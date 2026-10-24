# frozen_string_literal: true

class CreateRecipeIngredients < ActiveRecord::Migration[8.1]
  def change
    create_table :recipe_ingredients do |t|
      t.references :recipe, null: false, foreign_key: true
      t.references :ingredient, null: false, foreign_key: true
      t.decimal :quantity, precision: 10, scale: 3, null: false
      t.references :unit, null: true, foreign_key: true

      t.timestamps

      t.index [ :recipe_id, :ingredient_id ], unique: true
    end
  end
end
