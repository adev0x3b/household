# frozen_string_literal: true

class CreateMedications < ActiveRecord::Migration[8.1]
  def change
    create_table :medications do |t|
      t.references :event, null: false, foreign_key: true
      t.date :occurrence_date, null: false
      t.integer :status, null: false, default: 0
      t.string :name, null: false
      t.integer :kind, null: false
      t.decimal :quantity, precision: 10, scale: 2, null: false
      t.string :unit
      t.integer :area
      t.integer :side
      t.datetime :completed_at

      t.timestamps

      t.index [ :event_id, :occurrence_date ], unique: true
    end
  end
end
