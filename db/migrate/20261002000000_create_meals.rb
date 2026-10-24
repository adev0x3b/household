# frozen_string_literal: true

class CreateMeals < ActiveRecord::Migration[8.1]
  def change
    create_table :meals do |t|
      t.references :event, null: false, foreign_key: true
      t.date :occurrence_date, null: false
      t.integer :status, null: false, default: 0
      t.datetime :completed_at
      t.integer :kind, null: false, default: 0
      t.integer :meal_type
      t.string :title
      t.text :notes

      t.timestamps

      t.index [ :event_id, :occurrence_date ], unique: true
    end
  end
end
