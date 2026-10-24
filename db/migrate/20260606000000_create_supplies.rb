# frozen_string_literal: true

class CreateSupplies < ActiveRecord::Migration[8.1]
  def change
    create_table :supplies do |t|
      t.string :name, null: false
      t.integer :category, null: false, default: 0
      t.string :unit_label, null: false
      t.decimal :low_stock_threshold, precision: 10, scale: 3
      t.integer :pao_days

      t.timestamps
    end

    add_index :supplies, "LOWER(name)", unique: true, name: "index_supplies_on_lower_name"
  end
end
