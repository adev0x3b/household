# frozen_string_literal: true

module Reports
  module Agenda
    # The appointments that aren't medical (work, social, personal:
    # Appointment::Kind#section): whether they were kept, each day from one
    # OccurrenceLedger, and the ones coming up (the next 30 days), which are
    # as of today, whatever period is selected.
    class Appointments
      AHEAD_DAYS = 30
      OUTCOME_SERIES = Healthcare::Appointments::STATUS_SERIES

      Row = Data.define(:date, :title, :kind, :counterpart, :occurrence)
      KindRow = Data.define(:kind, :due, :attended, :rate)

      def initialize(period:, today:, window:)
        @period = period
        @today = today
        @window = window
      end

      def any? = entries_in(@period).any?

      def attendance_metric
        Metric.new(
          value: OccurrenceLedger.rate(entries_in(@period)),
          previous: OccurrenceLedger.rate(entries_in(@period.previous)),
          format: :percent, polarity: :higher_is_better,
        )
      end

      # The next appointments from today on, soonest first, with their kind
      # and who they're with.
      def upcoming_rows
        ahead = Period.new(start_date: @today, end_date: @today + AHEAD_DAYS)
        entries_in(ahead).select(&:to_come?).map do |entry|
          Row.new(
            date: entry.date, title: entry.label, kind: Appointment::Kind.new(kind_of(entry)),
            counterpart: entry.details.counterpart.presence, occurrence: entry.occurrence,
          )
        end.sort_by { |row| [ row.date, *clock_order(row.occurrence) ] }
      end

      # Attended, skipped, without an outcome, cancelled and still to come,
      # per bucket of the period.
      def outcomes_chart
        by_bucket = @period.per_bucket(entries_in(@period), &:date)

        Chart.new(
          kind: :stacked_bar, title: I18n.t("home.agenda.appointments.chart"),
          labels: @period.bucket_labels,
          series: OUTCOME_SERIES.map do |state, color|
            values = by_bucket.map { |entries| entries.count { |entry| entry.outcome == state } }
            Chart::Series.new(label: I18n.t("home.agenda.appointments.outcomes.#{state}"), values: values, color: color)
          end,
        )
      end

      # Attendance per kind of appointment (work, social…), the busiest first.
      def kind_rows
        entries_in(@period).select(&:due?).group_by { |entry| kind_of(entry) }
          .map do |kind, entries|
            KindRow.new(
              kind: Appointment::Kind.new(kind), due: entries.size, attended: entries.count(&:taken?),
              rate: OccurrenceLedger.rate(entries),
            )
          end
          .sort_by { |row| [ -row.due, Appointment::Kind::ALL.index(row.kind.name) ] }
      end

      private

      def entries
        @entries ||= begin
          span = Period.new(
            start_date: [ @period.previous.start_date, @today ].min,
            end_date: [ @period.end_date, @today + AHEAD_DAYS ].max,
          )
          @window.ledger(span, today: @today, of: Appointment) { _1.section == :agenda }.entries
        end
      end

      def entries_in(period) = entries.select { |entry| period.range.cover?(entry.date) }

      def kind_of(entry) = entry.details.kind.presence || Appointment::Kind::DEFAULT

      # Appointments with a start time by the clock, the untimed ones after
      # them.
      def clock_order(occurrence)
        time = occurrence.start_time
        time ? [ 0, time ] : [ 1 ]
      end
    end
  end
end
