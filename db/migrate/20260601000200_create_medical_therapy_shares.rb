# frozen_string_literal: true

class CreateMedicalTherapyShares < ActiveRecord::Migration[8.1]
  def change
    create_table :medical_therapy_shares do |t|
      t.references :medical_therapy, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true

      t.timestamps

      t.index [ :medical_therapy_id, :profile_id ], unique: true
    end
  end
end
