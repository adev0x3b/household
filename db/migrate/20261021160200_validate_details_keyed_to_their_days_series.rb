# frozen_string_literal: true

# Checks the details already there against the keys the previous migration
# added, each on its own without blocking writes, then drops the keys on the
# day alone, which refuse nothing the new ones don't. A row that pairs a day
# with another series stops the deploy here, with the key named, and the
# version still serving carries on: which of the two it meant is for a
# person to say.
class ValidateDetailsKeyedToTheirDaysSeries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  DETAILS = %i[appointment_details lab_test_result_details meal_details medication_details task_details
               transaction_details].freeze

  def up
    DETAILS.each do |table|
      validate_foreign_key table, name: "#{table}_day_of_its_series"
      remove_foreign_key table, :occurrences, column: :occurrence_id, if_exists: true
    end
  end

  def down
    DETAILS.each do |table|
      add_foreign_key table, :occurrences, column: :occurrence_id, on_delete: :cascade, if_not_exists: true
    end
  end
end
