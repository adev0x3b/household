# frozen_string_literal: true

# How many people a household may hold and how many each member may invite
# were constants in the code; they become limits the admin sets, like the
# day's budgets. A column left NULL is unset: no limit.
class AddPeopleLimitsToPlatformSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :platform_settings, :household_size, :integer
    add_column :platform_settings, :invitations_per_member, :integer

    add_check_constraint :platform_settings, "household_size > 0", name: "platform_settings_household_size_positive", validate: false
    add_check_constraint :platform_settings, "invitations_per_member > 0",
                         name: "platform_settings_invitations_per_member_positive", validate: false
  end
end
