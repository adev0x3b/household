# frozen_string_literal: true

class AddMedicalTherapyToEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :events, :medical_therapy, null: true, foreign_key: true
  end
end
