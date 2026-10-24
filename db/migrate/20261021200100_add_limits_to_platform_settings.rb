# frozen_string_literal: true

# What a copy lets its people do was read from its environment alone; it
# becomes a setting the admin changes in the browser, and the environment,
# where it names one, still decides and locks it. A column left NULL is
# unset: the switch is on, the count unlimited, the quota the default.
class AddLimitsToPlatformSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :platform_settings, :assistant, :boolean
    add_column :platform_settings, :uploads, :boolean
    add_column :platform_settings, :pictures, :boolean
    add_column :platform_settings, :invitations, :boolean
    add_column :platform_settings, :push_notifications, :boolean
    add_column :platform_settings, :release_check, :boolean
    add_column :platform_settings, :assistant_messages_per_day, :integer
    add_column :platform_settings, :book_lookups_per_day, :integer
    add_column :platform_settings, :files_quota, :bigint

    add_check_constraint :platform_settings, "assistant_messages_per_day >= 0",
                         name: "platform_settings_assistant_messages_per_day_not_negative", validate: false
    add_check_constraint :platform_settings, "book_lookups_per_day >= 0",
                         name: "platform_settings_book_lookups_per_day_not_negative", validate: false
    add_check_constraint :platform_settings, "files_quota > 0", name: "platform_settings_files_quota_positive", validate: false
  end
end
