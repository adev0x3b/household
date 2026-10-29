# frozen_string_literal: true

# Whether a reminder also comes by email (Emails::Kinds::Reminder). Every
# reminder set before keeps to the bell and the devices.
class AddByEmailToEventReminders < ActiveRecord::Migration[8.1]
  def change
    add_column :event_reminders, :by_email, :boolean, null: false, default: false
  end
end
