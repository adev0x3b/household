# frozen_string_literal: true

# The constraint the previous migration added, checked against the rows
# there are (a scan without a write lock), then the columns made NOT NULL —
# which Postgres does without scanning again, the constraint having proved
# it — and the constraint dropped. Outside a transaction, so one table's
# lock isn't held while the next is checked; each step is skipped once
# done, so a run cut short can simply run again.
class RequireDayRecordsHaveTheirDay < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TABLES = %i[lab_test_result_entries meal_consumptions supply_consumptions].freeze

  def up
    TABLES.each do |table|
      name = "#{table}_occurrence_id_null"
      next unless check_constraint_exists?(table, name: name)

      validate_check_constraint table, name: name
      change_column_null table, :occurrence_id, false
      remove_check_constraint table, name: name
    end
  end

  def down
    TABLES.each do |table|
      change_column_null table, :occurrence_id, true
      add_check_constraint table, "occurrence_id IS NOT NULL", name: "#{table}_occurrence_id_null", validate: false
    end
  end
end
