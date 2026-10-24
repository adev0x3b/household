# frozen_string_literal: true

# The personal details no page ever asked for or showed: an address, a birth
# date and age, three phone numbers, a tax number, and a "locked" flag
# Devise's lockable replaced. Profile has ignored them since ce06d48 and
# e1c5740, which production runs, so no version serving reads or writes them. Profile.ignored_columns goes in the deploy after this one.
class DropUnusedProfileDetails < ActiveRecord::Migration[8.1]
  def change
    # zero-downtime: the version still serving ignores every one of these columns (Profile.ignored_columns), so it never selects or inserts them.
    safety_assured do
      remove_columns :profiles, :address, :city, :state, :zip_code, :country, :phone_number, :mobile_number, :fax_number, :ssn, type: :string
      remove_column :profiles, :birth_date, :datetime
      remove_column :profiles, :age, :integer
      remove_column :profiles, :locked, :boolean, default: false, null: false
    end
  end
end
