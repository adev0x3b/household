# frozen_string_literal: true

class CreateEventShares < ActiveRecord::Migration[8.1]
  def change
    create_table :event_shares do |t|
      t.references :event, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true

      t.timestamps

      t.index [ :event_id, :profile_id ], unique: true
    end
  end
end
