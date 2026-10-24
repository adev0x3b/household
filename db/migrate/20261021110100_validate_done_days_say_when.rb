# frozen_string_literal: true

# Checks the days already there against the previous migration's
# constraint. Validating scans the table without blocking its writes. A day
# that breaks it stops the deploy here, with the constraint named, and the
# version still serving carries on: whether such a day was done, and when,
# is for a person to say.
class ValidateDoneDaysSayWhen < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    validate_check_constraint :occurrences, name: "occurrences_completed_at_with_completed"
  end

  # A validated constraint is the one that was added; the previous
  # migration's rollback drops it.
  def down; end
end
