# frozen_string_literal: true

# When a link to set a password stops working, for a link that lasts less
# than Devise's two days: one mailed to the person, or printed on the
# server. Empty on every existing profile, whose links keep the two days.
class AddResetPasswordExpiresAtToProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :reset_password_expires_at, :datetime
  end
end
