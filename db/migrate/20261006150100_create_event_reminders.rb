# frozen_string_literal: true

# Due reminders: each person who has an event picks how long before each of
# its occurrences they want to hear about it (Reminders::DispatchJob). A
# delivery row per reminder and occurrence makes sending happen once.
# A profile's time zone places "3 hours before" on their clock.
class CreateEventReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :event_reminders do |t|
      t.references :event, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.integer :offset_minutes, null: false
      t.timestamps
    end
    add_index :event_reminders, %i[event_id profile_id offset_minutes], unique: true

    create_table :event_reminder_deliveries do |t|
      t.references :event_reminder, null: false, foreign_key: true, index: false
      t.date :occurrence_date, null: false
      t.datetime :created_at, null: false
    end
    add_index :event_reminder_deliveries, %i[event_reminder_id occurrence_date], unique: true

    add_column :profiles, :time_zone, :string
  end
end
