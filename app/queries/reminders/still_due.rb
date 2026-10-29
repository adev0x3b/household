# frozen_string_literal: true

module Reminders
  # Which of a person's reminder mails in the outbox (Emails::Kinds::Reminder)
  # are still worth sending, and what each reminds of: its reminder still
  # asks for email, the person may still read the series, and the day is
  # still to do at that time and not yet due, by the series as it is now.
  # The reminders, the series the person may read and their days are read
  # once for all the rows.
  #
  #   Reminders::StillDue.new(profile, rows).to_a
  #   # => [ #<data Reminders::StillDue::Reminder row=…, occurrence=…, due_at=…, timed=true>, … ], soonest due first
  class StillDue
    Reminder = Data.define(:row, :occurrence, :due_at, :timed)

    def initialize(profile, rows, now: Time.current)
      @profile = profile
      @rows = rows
      @now = now
    end

    def to_a
      reminders = EventReminder.where(id: @rows.map { _1.data["event_reminder_id"] }, profile_id: @profile.id, by_email: true).index_by(&:id)
      events = Event.accessible_by(@profile).where(id: reminders.values.map(&:event_id)).index_by(&:id)
      dates = @rows.map { date_of(_1) }
      Event.preload_occurrences(events.values, dates.min, dates.max) if events.any?
      @rows.filter_map { |row| still_due(row, events[reminders[row.data["event_reminder_id"]]&.event_id]) }.sort_by(&:due_at)
    end

    private

    def still_due(row, event)
      return unless event

      date = date_of(row)
      occurrence = event.occurrences_between(date, date).find { _1.time_string == row.data["time"] }
      return unless occurrence&.open?

      due_at, timed = DueAt.for(occurrence, @profile.zone)
      Reminder.new(row: row, occurrence: occurrence, due_at: due_at, timed: timed) if due_at > @now
    end

    def date_of(row) = Date.iso8601(row.data.fetch("date"))
  end
end
