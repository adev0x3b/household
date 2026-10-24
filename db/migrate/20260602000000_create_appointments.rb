# frozen_string_literal: true

class CreateAppointments < ActiveRecord::Migration[8.1]
  def change
    create_table :appointments do |t|
      t.references :event, null: false, foreign_key: true
      t.date :occurrence_date, null: false
      t.integer :status, null: false, default: 0
      t.string :title, null: false
      t.string :provider
      t.string :location
      t.text :notes
      t.datetime :completed_at

      t.timestamps

      t.index [ :event_id, :occurrence_date ], unique: true
    end
  end
end
