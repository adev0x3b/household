# frozen_string_literal: true

class CreateLabTestResults < ActiveRecord::Migration[8.1]
  def change
    create_table :lab_test_results do |t|
      t.references :event, null: false, foreign_key: true
      t.date :occurrence_date, null: false
      t.integer :status, null: false, default: 0
      t.string :title, null: false
      t.text :notes
      t.datetime :completed_at

      t.timestamps

      t.index [ :event_id, :occurrence_date ], unique: true
    end
  end
end
