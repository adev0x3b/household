# frozen_string_literal: true

# What the installation mails and through which relay: the switch, the
# budgets (the installation's hour and day, a household's reminders in a
# day) and the relay itself, its password encrypted like the other secrets.
# A relay field left NULL is the environment's (Emails::RelaySettings); a
# switch left NULL reads as on and a budget as its default (Platform), so
# StartOutgoingMailFromTheEnvironment copies the environment's onto a row
# that exists.
class AddOutgoingMailToPlatformSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :platform_settings, :outgoing_mail, :boolean
    add_column :platform_settings, :mails_per_hour, :integer
    add_column :platform_settings, :mails_per_day, :integer
    add_column :platform_settings, :reminder_mails_per_day, :integer
    add_column :platform_settings, :smtp_host, :string
    add_column :platform_settings, :smtp_port, :integer
    add_column :platform_settings, :smtp_username, :string
    add_column :platform_settings, :smtp_password, :text
    add_column :platform_settings, :smtp_tls, :string
    add_column :platform_settings, :mail_from, :string

    add_check_constraint :platform_settings, "mails_per_hour >= 2", name: "platform_settings_mails_per_hour_at_least_two", validate: false
    add_check_constraint :platform_settings, "mails_per_day >= 6", name: "platform_settings_mails_per_day_at_least_six", validate: false
    add_check_constraint :platform_settings, "reminder_mails_per_day >= 0", name: "platform_settings_reminder_mails_per_day_not_negative",
                                                                            validate: false
    add_check_constraint :platform_settings, "smtp_port BETWEEN 1 AND 65535", name: "platform_settings_smtp_port_is_a_port", validate: false
  end
end
