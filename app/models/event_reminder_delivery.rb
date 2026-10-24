# frozen_string_literal: true

# A reminder that was sent for one day (one slot of it). The unique index
# on (event_reminder_id, date, time) is what makes Reminders::DispatchJob
# send each one once per slot, even when two runs overlap (an untimed day
# has a nil time, counted as one value). A delivery is a fact about the
# schedule, not about a stored day, so it is keyed by the slot, never by an
# Occurrence row.
class EventReminderDelivery < ApplicationRecord
  belongs_to :event_reminder
end
