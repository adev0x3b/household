# frozen_string_literal: true

module Events
  # Sets one person's reminders on an event to what their form says:
  #
  #   Events::SetReminders.call(event, profile:, entries: [ { amount: "2", unit: "days" }, { amount: "3", unit: "hours" } ])
  #
  # Rows that can't be a reminder (blank, zero, beyond 30 days, an unknown
  # unit; the form doesn't let them through) and repeats are dropped, and at
  # most EventReminder::MAX_PER_EVENT are kept. Reminders that stay keep
  # their row, so what they already sent isn't sent again.
  class SetReminders
    def self.call(event, profile:, entries:)
      offsets = Array(entries).filter_map { offset_of(_1) }.uniq.first(EventReminder::MAX_PER_EVENT)
      current = event.event_reminders.for_profile(profile)

      current.where.not(offset_minutes: offsets).destroy_all
      (offsets - current.pluck(:offset_minutes)).each do |offset|
        event.event_reminders.create!(profile: profile, offset_minutes: offset)
      end
    end

    def self.offset_of(entry)
      entry = entry.to_h.with_indifferent_access
      amount = Integer(entry[:amount].to_s, exception: false)
      minutes = EventReminder::UNITS[entry[:unit].to_s]
      return unless amount && minutes && amount.positive?

      offset = amount * minutes
      offset if offset <= EventReminder::MAX_OFFSET
    end
    private_class_method :offset_of
  end
end
