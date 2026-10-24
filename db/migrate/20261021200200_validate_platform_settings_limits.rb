# frozen_string_literal: true

# Checks the row already there against the previous migration's
# constraints, without blocking its writes. Its new columns are all NULL,
# so nothing breaks them.
class ValidatePlatformSettingsLimits < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  CONSTRAINTS = %w[platform_settings_assistant_messages_per_day_not_negative platform_settings_book_lookups_per_day_not_negative
                   platform_settings_files_quota_positive].freeze

  def up
    CONSTRAINTS.each { |name| validate_check_constraint :platform_settings, name: name }
  end

  # A validated constraint is the one that was added; the previous
  # migration's rollback drops it.
  def down; end
end
