# frozen_string_literal: true

class CreateMealConsumptions < ActiveRecord::Migration[8.1]
  def change
    create_table :meal_consumptions do |t|
      t.references :meal, null: false, foreign_key: true
      t.references :ingredient, null: false, foreign_key: true
      t.decimal :quantity, precision: 10, scale: 3, null: false

      t.timestamps
    end
  end
end
