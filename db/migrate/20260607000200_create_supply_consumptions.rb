# frozen_string_literal: true

class CreateSupplyConsumptions < ActiveRecord::Migration[8.1]
  def change
    create_table :supply_consumptions do |t|
      t.references :supply, null: false, foreign_key: true
      t.references :supply_purchase, null: true, foreign_key: true
      t.references :medication, null: true, foreign_key: true
      t.decimal :quantity, precision: 10, scale: 3, null: false
      t.datetime :consumed_at, null: false

      t.timestamps
    end
  end
end
