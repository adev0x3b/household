# frozen_string_literal: true

module Reminders
  # When a day is due, on its person's clock, for "2 hours before": an
  # appointment at its start time, a dose at its slot, a meal at its usual
  # hour, anything else (a date without a time) in the morning — each kind
  # answers for itself (Event#due_clock). The hours live in Events::TimesOfDay.
  #
  #   Reminders::DueAt.for(occurrence, zone) # => [ Thu 9 Oct 14:30 +02:00, true ]
  #
  # Returns the time and whether the thing has a time of its own (the
  # notification then says the hour, else the day alone).
  module DueAt
    def self.for(occurrence, zone)
      (hour, minute), timed = occurrence.event.due_clock(occurrence)
      date = occurrence.date
      [ zone.local(date.year, date.month, date.day, hour, minute), timed ]
    end
  end
end
