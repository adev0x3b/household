# frozen_string_literal: true

module Reports
  # Every day of some series inside a Period, each classified exactly once.
  # This is the single source of truth for adherence and attendance style
  # metrics.
  #
  #   window.ledger(period, today: today, of: Medication)   # Reports::Window
  #
  # `events` are series loaded with their days over the period (a
  # Reports::Window's, which a page loads once); the ledger iterates their
  # days with Event#occurrences_between — dates × slots minus exclusions,
  # saved or not — from memory. Whether a day has a row is an implementation
  # detail: a past day with none is simply :missed.
  #
  # States, from the day's status:
  #   :taken      completed
  #   :skipped    explicitly skipped (a decision, but still not taken)
  #   :cancelled  cancelled, so no longer expected and never counted as due
  #   :missed     its date has passed, not completed/skipped/cancelled
  #   :due_today  today, not done yet (not missed yet either)
  #   :upcoming   in the future
  #
  # Every saved day's own details row comes with the window, one query per
  # kind (Event.preload_occurrences → Occurrence.preload_details), so reading
  # `entry.details`, `entry.label` or a meal's recipes asks nothing more.
  class OccurrenceLedger
    # One day of a series and its state. `record` is the day itself once it
    # has a row and nil while it is projected (the calendar's "nothing
    # stored yet"); `time` is its slot ("HH:MM", nil for an untimed day) and
    # `anchor` the anchor the slot came from ("CM", with breakfast).
    Entry = Data.define(:occurrence, :state) do
      delegate :event, :date, :anchor, :details, :days_offset, to: :occurrence

      def time = occurrence.time_string
      def record = occurrence.persisted? ? occurrence : nil
      def label = occurrence.event_label

      def taken? = state == :taken
      def skipped? = state == :skipped
      def cancelled? = state == :cancelled
      def missed? = state == :missed
      def due_today? = state == :due_today
      def upcoming? = state == :upcoming

      # What a rate counts: a day done, skipped or let pass. A cancelled day
      # was never expected, and one still to come can't be judged yet.
      def due? = taken? || skipped? || missed?

      def to_come? = due_today? || upcoming?

      # The state a chart of outcomes draws, where today's days and later
      # ones are all still to come.
      def outcome = to_come? ? :upcoming : state
    end

    def self.rate(entries)
      due = entries.select(&:due?)
      return nil if due.empty?

      (due.count(&:taken?) * 100.0 / due.size).round(1)
    end

    def initialize(events:, period:, today: Date.current)
      @events = events
      @period = period
      @today = today
    end

    def entries
      @entries ||= begin
        occurrences = @events.flat_map { |event| event.occurrences_between(@period.start_date, @period.end_date) }
        occurrences.map { |occurrence| entry(occurrence) }.sort_by { |entry| [ entry.date, entry.time.to_s ] }
      end
    end

    def rate = self.class.rate(entries)

    def by_event = entries.group_by(&:event)

    private

    def entry(occurrence) = Entry.new(occurrence: occurrence, state: state_for(occurrence))

    def state_for(occurrence)
      if occurrence.completed? then :taken
      elsif occurrence.cancelled? then :cancelled
      elsif occurrence.skipped? then :skipped
      elsif occurrence.date < @today then :missed
      elsif occurrence.date == @today then :due_today
      else :upcoming
      end
    end
  end
end
