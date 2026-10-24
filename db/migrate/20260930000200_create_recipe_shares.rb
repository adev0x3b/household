# frozen_string_literal: true

class CreateRecipeShares < ActiveRecord::Migration[8.1]
  def change
    create_table :recipe_shares do |t|
      t.references :recipe, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true

      t.timestamps

      t.index [ :recipe_id, :profile_id ], unique: true
    end
  end
end
