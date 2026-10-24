# frozen_string_literal: true

# What a day recorded — a lab value, what a meal or a dose really drew —
# always belongs to that day (a required belongs_to), but the database
# would take one without. First a constraint for new rows, not yet checked
# against the table (no long lock); the next migration checks it and makes
# the columns NOT NULL.
class CheckDayRecordsHaveTheirDay < ActiveRecord::Migration[8.1]
  TABLES = %i[lab_test_result_entries meal_consumptions supply_consumptions].freeze

  def change
    TABLES.each do |table|
      add_check_constraint table, "occurrence_id IS NOT NULL", name: "#{table}_occurrence_id_null", validate: false
    end
  end
end
