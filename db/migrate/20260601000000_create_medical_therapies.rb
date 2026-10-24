# frozen_string_literal: true

class CreateMedicalTherapies < ActiveRecord::Migration[8.1]
  def change
    create_table :medical_therapies do |t|
      t.references :profile, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :status, null: false, default: 0

      t.timestamps
    end
  end
end
