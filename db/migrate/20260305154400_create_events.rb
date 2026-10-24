# frozen_string_literal: true

class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :profile, null: false, foreign_key: true
      t.string :eventable_type, null: false

      t.date :date, null: false
      t.text :recurrence_rule
      t.jsonb :excluded_dates, default: []

      t.timestamps
    end

    add_index :events, :date
    add_index :events, :eventable_type
    add_index :events, [ :profile_id, :eventable_type ]
  end
end
