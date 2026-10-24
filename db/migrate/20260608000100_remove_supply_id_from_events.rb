# frozen_string_literal: true

class RemoveSupplyIdFromEvents < ActiveRecord::Migration[8.1]
  def change
    remove_reference :events, :supply, foreign_key: true
  end
end
