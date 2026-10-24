# frozen_string_literal: true

# Other names of a profile's analyte, kept when two analytes are merged
# ("Vit D" into "Vitamin D"), so a report that says the old name finds it.
class CreateAnalyteAliases < ActiveRecord::Migration[8.1]
  def change
    create_table :analyte_aliases do |t|
      t.references :analyte, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :analyte_aliases, "profile_id, lower((name)::text)", unique: true, name: "index_analyte_aliases_on_profile_id_and_lower_name"
  end
end
