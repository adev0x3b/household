# frozen_string_literal: true

class DropInjections < ActiveRecord::Migration[8.1]
  def change
    drop_table :injections do |t|
      t.references :event, null: false, foreign_key: true

      t.date :occurrence_date, null: false
      t.string :name, null: false
      t.decimal :quantity, precision: 10, scale: 2, null: false
      t.integer :area, null: false
      t.integer :side, null: false
      t.integer :status, default: 0, null: false
      t.datetime :completed_at

      t.timestamps

      t.index :occurrence_date
      t.index [ :event_id, :occurrence_date ], unique: true
    end
  end
end
