# frozen_string_literal: true

class AddProfileToAnalytes < ActiveRecord::Migration[8.1]
  def up
    add_reference :analytes, :profile, foreign_key: true

    profiles = Profile.order(:created_at).to_a
    owner = profiles.first
    Analyte.update_all(profile_id: owner.id) if owner

    # The old global-uniqueness index must go before seeding other profiles'
    # standards below, or a name shared with the first profile's analytes
    # (e.g. "Glucose") collides at the DB level despite being scoped by
    # profile_id at the Ruby level.
    remove_index :analytes, name: "index_analytes_on_lower_name"
    add_index :analytes, "profile_id, LOWER(name)", unique: true, name: "index_analytes_on_profile_id_and_lower_name"

    profiles.drop(1).each { |profile| Analyte.seed_standards_for!(profile) }

    change_column_null :analytes, :profile_id, false
  end

  def down
    remove_index :analytes, name: "index_analytes_on_profile_id_and_lower_name"
    add_index :analytes, "LOWER(name)", unique: true, name: "index_analytes_on_lower_name"
    remove_reference :analytes, :profile
  end
end
