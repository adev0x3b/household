# frozen_string_literal: true

# The RFC 5545 RRULE line stored in `events.rrule`, built from the plain
# recurrence fields every form (Views::Occurrences::EventFields) and the
# assistant's payloads share: frequency, interval, week_days, ends. ice_cube
# reads and writes the line; the schedule's start is the series' starts_on
# (Events::Schedule).
#
#   Events::RecurrenceRule.build(frequency: "weekly", interval: 2, week_days: %w[monday friday])
#   # => "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR"
#   Events::RecurrenceRule.describe("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR")
#   # => { frequency: "weekly", interval: 2, week_days: ["monday", "friday"] }
#
# Returns nil for a one-off (blank frequency or "none").
module Events
  module RecurrenceRule
    FREQUENCIES = %w[daily weekly monthly yearly].freeze
    WEEK_DAYS   = %w[monday tuesday wednesday thursday friday saturday sunday].freeze

    # What was given can't make a rule (an end that isn't a date).
    Invalid = Class.new(ArgumentError)

    # A stored line as a form's fields, every one filled in: "none" and
    # its defaults for a one-off.
    Fields = Data.define(:frequency, :interval, :week_days, :ends) do
      def self.one_off = new(frequency: "none", interval: 1, week_days: [], ends: nil)

      def repeats? = frequency != "none"
    end

    module_function

    # ends: the last day it can happen (a Date or "YYYY-MM-DD"; anything else
    # raises Invalid). Ending a series keeps its past days on the calendar —
    # unlike removing the repeat, which leaves only the first date.
    def build(frequency:, interval: 1, week_days: nil, ends: nil)
      frequency = frequency.to_s
      return nil unless FREQUENCIES.include?(frequency)

      rule = IceCube::Rule.public_send(frequency, [ interval.to_i, 1 ].max)

      days = Array(week_days).map { |d| d.to_s.downcase } & WEEK_DAYS
      rule = rule.day(*days.map(&:to_sym)) if frequency == "weekly" && days.any?
      rule = rule.until(midnight(end_date(ends)).end_of_day) if ends.present?

      rule.to_ical
    end

    def end_date(ends)
      ends.is_a?(Date) ? ends : Date.iso8601(ends.to_s)
    rescue Date::Error
      raise Invalid, "the end #{ends.inspect} is not a date"
    end

    # A date as ice_cube walks it: its midnight in UTC, never in the process's
    # zone, so an end written by one machine is the same day on any other.
    def midnight(date) = Time.utc(date.year, date.month, date.day)

    # The ice_cube rule for a stored line. Raises on a line it can't read.
    def parse(rrule)
      raise ArgumentError, "blank rule" if rrule.blank?

      IceCube::Rule.from_ical(rrule.to_s.delete_prefix("RRULE:"))
    end

    # The fields of a stored line as a form shows them. A line ice_cube
    # can't read (it raises ArgumentError for any of its reasons) is a
    # broken row: reported, and shown as a one-off rather than breaking
    # the form that would let someone set it right.
    def fields(rrule)
      described = describe(rrule)
      return Fields.one_off unless FREQUENCIES.include?(described[:frequency])

      Fields.new(frequency: described[:frequency], interval: described[:interval] || 1,
                 week_days: Array(described[:week_days]), ends: described[:ends])
    rescue ArgumentError => e
      Rails.error.report(e, handled: true, context: { rrule: rrule })
      Fields.one_off
    end

    # The pattern of a line: how it repeats, apart from when it ends. Two
    # lines with one pattern are the same series stopping at different days.
    def pattern(rrule) = describe(rrule).except(:ends)

    # Inverse of .build — the plain fields for a stored line, so a form or
    # the assistant can describe a series without knowing ice_cube.
    def describe(rrule)
      return { frequency: "none" } if rrule.blank?

      rule = parse(rrule)
      hash = rule.to_hash
      {
        frequency: hash[:rule_type].to_s.demodulize.delete_suffix("Rule").downcase,
        interval: hash[:interval],
        week_days: Array(hash.dig(:validations, :day)).map { |i| WEEK_DAYS[(i - 1) % 7] },
        ends: rule.until_time&.utc&.to_date
      }.compact
    end
  end
end
