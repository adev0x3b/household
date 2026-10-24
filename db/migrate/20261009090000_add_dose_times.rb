# frozen_string_literal: true

# A medication taken several times a day: the series lists its doses of the
# day (events.times_of_day: "HH:MM" or a FHIR event-timing anchor such as
# CM, with breakfast), and each dose is its own record with the time it was
# scheduled at, where the time it came from (the anchor, for the label) and,
# when not taken, why (FHIR statusReason). One record per (event, date,
# time); an untimed dose keeps the one-per-day rule through NULLS NOT
# DISTINCT. A reminder is sent once per dose, not per day.
class AddDoseTimes < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :times_of_day, :jsonb, null: false, default: []

    add_column :medications, :scheduled_time, :time
    add_column :medications, :timing_anchor, :string
    add_column :medications, :not_taken_reason, :integer
    remove_index :medications, name: "index_medications_on_event_id_and_occurrence_date",
                               column: [ :event_id, :occurrence_date ], unique: true
    add_index :medications, [ :event_id, :occurrence_date, :scheduled_time ], unique: true, nulls_not_distinct: true,
                                                                              name: "index_medications_on_event_id_and_occurrence"

    add_column :event_reminder_deliveries, :occurrence_time, :time
    remove_index :event_reminder_deliveries, name: "idx_on_event_reminder_id_occurrence_date_0250a037ac",
                                             column: [ :event_reminder_id, :occurrence_date ], unique: true
    add_index :event_reminder_deliveries, [ :event_reminder_id, :occurrence_date, :occurrence_time ], unique: true,
                                                                                                      nulls_not_distinct: true, name: "index_event_reminder_deliveries_on_reminder_and_occurrence"
  end
end
