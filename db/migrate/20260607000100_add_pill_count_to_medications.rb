# frozen_string_literal: true

class AddPillCountToMedications < ActiveRecord::Migration[8.1]
  def change
    add_column :medications, :pill_count, :decimal, precision: 10, scale: 3
  end
end
