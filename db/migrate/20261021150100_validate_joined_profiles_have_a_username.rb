# frozen_string_literal: true

# Checks the profiles already there against the previous migration's
# constraint. Validating scans the table without blocking its writes. A
# profile that breaks it stops the deploy here, with the constraint named,
# and the version still serving carries on: a person's username is theirs
# to choose.
class ValidateJoinedProfilesHaveAUsername < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    validate_check_constraint :profiles, name: "profiles_username_unless_invited"
  end

  # A validated constraint is the one that was added; the previous
  # migration's rollback drops it.
  def down; end
end
