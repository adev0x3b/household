# frozen_string_literal: true

class CreateInjections < ActiveRecord::Migration[8.1]
  def change
    create_table :injections do |t|
      t.references :event, null: false, foreign_key: true

      t.date :occurrence_date, null: false
      t.string :name, null: false
      t.decimal :quantity, precision: 10, scale: 2, null: false
      t.integer :area, null: false
      t.integer :side, null: false
      t.integer :status, default: 0, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :injections, :occurrence_date
    add_index :injections, [ :event_id, :occurrence_date ], unique: true
  end
end
