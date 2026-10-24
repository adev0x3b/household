# frozen_string_literal: true

# Checks the rows already there against the constraints the previous
# migration added. Validating scans a table without blocking its writes,
# and each one runs on its own, outside a transaction, so a run cut short
# can simply run again. A row that breaks a rule stops the deploy here, with
# the constraint named, and the version still serving carries on.
class ValidateTheChecksTheModelsPromise < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    connection.tables.each do |table|
      check_constraints(table).reject(&:validated?).each do |constraint|
        validate_check_constraint table, name: constraint.name
      end
    end
  end

  # A validated constraint is the one that was added; the previous
  # migration's rollback drops it.
  def down; end
end
