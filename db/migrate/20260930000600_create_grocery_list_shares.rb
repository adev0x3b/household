# frozen_string_literal: true

class CreateGroceryListShares < ActiveRecord::Migration[8.1]
  def change
    create_table :grocery_list_shares do |t|
      t.references :grocery_list, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true

      t.timestamps

      t.index [ :grocery_list_id, :profile_id ], unique: true
    end
  end
end
