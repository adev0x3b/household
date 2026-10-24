# frozen_string_literal: true

class CreateReferenceRanges < ActiveRecord::Migration[8.1]
  def change
    create_table :reference_ranges do |t|
      t.references :analyte, null: false, foreign_key: true
      t.references :unit, null: false, foreign_key: true
      t.integer :sex, null: false, default: 0
      t.decimal :low, precision: 10, scale: 3
      t.decimal :high, precision: 10, scale: 3
      t.decimal :critical_low, precision: 10, scale: 3
      t.decimal :critical_high, precision: 10, scale: 3

      t.timestamps

      t.index [ :analyte_id, :unit_id, :sex ], unique: true, name: "index_reference_ranges_on_analyte_unit_sex"
    end
  end
end
