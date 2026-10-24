# frozen_string_literal: true

class AddSupplyIdToEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :events, :supply, null: true, foreign_key: true
  end
end
