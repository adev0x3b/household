# frozen_string_literal: true

module Events
  # Sets one person's reminders on an event to what their form says:
  #
  #   Events::SetReminders.call(event, profile:, entries: [ { amount: "2", unit: "days", by_email: "1" }, { amount: "3", unit: "hours" } ])
  #
  # Rows that can't be a reminder (blank, zero, beyond 30 days, an unknown
  # unit; the form doesn't let them through) and repeats are dropped, and at
  # most EventReminder::MAX_PER_EVENT are kept. Reminders that stay keep
  # their row, so what they already sent isn't sent again.
  #
  # Whether a reminder comes by email too is what its row says. A row that
  # says nothing, from a form drawn while mail wasn't the person's to have,
  # leaves a reminder that stays as it was, and makes a new one the bell's
  # alone. Repeats come by email if any of them asks.
  class SetReminders
    def self.call(event, profile:, entries:)
      wanted = wanted(entries)
      current = event.event_reminders.for_profile(profile)

      current.where.not(offset_minutes: wanted.keys).destroy_all
      [ true, false ].each do |by_email|
        offsets = wanted.select { |_offset, said| said == by_email }.keys
        current.where(offset_minutes: offsets).where.not(by_email: by_email).update_all(by_email: by_email, updated_at: Time.current) if offsets.any?
      end
      (wanted.keys - current.pluck(:offset_minutes)).each do |offset|
        event.event_reminders.create!(profile: profile, offset_minutes: offset, by_email: wanted[offset] || false)
      end
    end

    # The reminders asked for, in the order of the rows, each with whether
    # it comes by email: true or false when a row says, nil when none does.
    def self.wanted(entries)
      Array(entries).each_with_object({}) do |entry, wanted|
        entry = entry.to_h.with_indifferent_access
        offset = offset_of(entry)
        next if offset.nil? || (!wanted.key?(offset) && wanted.size >= EventReminder::MAX_PER_EVENT)

        said = [ wanted[offset], by_email_of(entry) ].compact
        wanted[offset] = said.empty? ? nil : said.include?(true)
      end
    end

    def self.offset_of(entry)
      amount = Integer(entry[:amount].to_s, exception: false)
      minutes = EventReminder::UNITS[entry[:unit].to_s]
      return unless amount && minutes && amount.positive?

      offset = amount * minutes
      offset if offset <= EventReminder::MAX_OFFSET
    end

    # The form sends "0" before the box, so a row drawn with the box always says.
    def self.by_email_of(entry)
      return unless entry.key?(:by_email)

      ActiveModel::Type::Boolean.new.cast(entry[:by_email]) || false
    end
    private_class_method :wanted, :offset_of, :by_email_of
  end
end
