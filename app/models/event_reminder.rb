# frozen_string_literal: true

# "Tell me 2 days before": one person's reminder on an event, for every one of
# its occurrences that is still to do. Each person who has the event keeps
# their own (Events::SetReminders from the forms);
# Reminders::DispatchJob sends them as `reminder_due` notifications.
class EventReminder < ApplicationRecord
  UNITS = { "hours" => 60, "days" => 24 * 60 }.freeze
  MAX_OFFSET = 30.days.in_minutes.to_i
  MAX_PER_EVENT = 5

  belongs_to :event
  belongs_to :profile
  has_many :deliveries, class_name: "EventReminderDelivery", dependent: :delete_all

  validates :offset_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_OFFSET }
  validates :offset_minutes, uniqueness: { scope: %i[event_id profile_id] }

  scope :for_profile, ->(profile) { where(profile: profile) }

  # Back to what the form shows: the largest unit that divides it.
  def amount_and_unit
    unit = offset_minutes % UNITS["days"] == 0 ? "days" : "hours"
    [ offset_minutes / UNITS[unit], unit ]
  end

  def offset = offset_minutes.minutes
end
