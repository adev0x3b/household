# frozen_string_literal: true

# Checks the row already there against the previous migration's
# constraints, without blocking its writes. Its new columns are all NULL,
# so nothing breaks them.
class ValidatePlatformSettingsPeopleLimits < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  CONSTRAINTS = %w[platform_settings_household_size_positive platform_settings_invitations_per_member_positive].freeze

  def up
    CONSTRAINTS.each { |name| validate_check_constraint :platform_settings, name: name }
  end

  # A validated constraint is the one that was added; the previous
  # migration's rollback drops it.
  def down; end
end
