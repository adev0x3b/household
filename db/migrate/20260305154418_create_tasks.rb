# frozen_string_literal: true

class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :event, null: false, foreign_key: true

      t.date :occurrence_date, null: false
      t.string :title, null: false
      t.text :description
      t.integer :priority, default: 0, null: false
      t.integer :status, default: 0, null: false

      t.timestamps
    end

    add_index :tasks, :occurrence_date
    add_index :tasks, [ :event_id, :occurrence_date ], unique: true
  end
end
