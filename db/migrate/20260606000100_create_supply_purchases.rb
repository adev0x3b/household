# frozen_string_literal: true

class CreateSupplyPurchases < ActiveRecord::Migration[8.1]
  def change
    create_table :supply_purchases do |t|
      t.references :supply, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.references :medical_therapy, null: true, foreign_key: true
      t.decimal :quantity_purchased, precision: 10, scale: 3, null: false
      t.decimal :quantity_remaining, precision: 10, scale: 3, null: false
      t.date :purchased_on, null: false
      t.date :expires_on
      t.date :opened_on
      t.integer :pao_days_override

      t.timestamps
    end
  end
end
