# frozen_string_literal: true

# Devise's lockable: wrong passwords in a row, and since when an account
# waits (config/initializers/devise.rb). Unlocking is by time alone, so no
# unlock token.
class AddLockingToProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :failed_attempts, :integer, null: false, default: 0
    add_column :profiles, :locked_at, :datetime
  end
end
