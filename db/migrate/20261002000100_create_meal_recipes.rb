# frozen_string_literal: true

class CreateMealRecipes < ActiveRecord::Migration[8.1]
  def change
    create_table :meal_recipes do |t|
      t.references :meal, null: false, foreign_key: true
      t.references :recipe, null: false, foreign_key: true

      t.timestamps

      t.index [ :meal_id, :recipe_id ], unique: true
    end
  end
end
