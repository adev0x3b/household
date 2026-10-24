# frozen_string_literal: true

class MakeQuantityNullableOnMedications < ActiveRecord::Migration[8.1]
  def change
    change_column_null :medications, :quantity, true
  end
end
