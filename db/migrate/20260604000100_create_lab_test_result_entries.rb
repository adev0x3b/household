# frozen_string_literal: true

class CreateLabTestResultEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :lab_test_result_entries do |t|
      t.references :lab_test_result, null: false, foreign_key: true
      t.string :key, null: false
      t.string :value, null: false
      t.string :unit

      t.timestamps

      t.index [ :lab_test_result_id, :key ], unique: true
    end
  end
end
