# frozen_string_literal: true

module Reports
  module Healthcare
    # Attendance at medical appointments (Appointment series whose kind
    # belongs to Healthcare) for a period, from an OccurrenceLedger.
    # attendance = attended ÷ due (same due rule as doses). Who a visit is
    # with is its details' counterpart (a provider, for this kind).
    class Appointments
      UPCOMING_LIMIT = 3
      UPCOMING_HORIZON_DAYS = 180

      # Outcome → color token. Status colors carry meaning here, and the
      # legend always names them, so color is never the only cue.
      STATUS_SERIES = {
        taken: "good",
        missed: "critical",
        skipped: "warning",
        cancelled: "neutral",
        upcoming: "series-1"
      }.freeze

      Upcoming = Data.define(:date, :title, :counterpart, :occurrence)
      CounterpartRow = Data.define(:counterpart, :due, :attended, :rate)

      def initialize(audience:, period:, today: Date.current, window: Window.new(audience))
        @audience = audience
        @period = period
        @today = today
        @window = window
      end

      # The healthcare visits' days in a period: the appointments whose kind
      # is medical.
      def self.visits(window, period, today:) = window.ledger(period, today: today, of: Appointment) { _1.section == :healthcare }

      def any? = ledger.entries.any?

      def attendance_metric
        Metric.new(value: ledger.rate, previous: previous_ledger.rate, format: :percent, polarity: :higher_is_better)
      end

      def status_chart
        by_bucket = @period.per_bucket(ledger.entries, &:date)

        Chart.new(
          kind: :stacked_bar, title: I18n.t("home.healthcare.appointments.status_chart"),
          labels: @period.bucket_labels,
          series: STATUS_SERIES.map do |state, color|
            values = by_bucket.map { |entries| entries.count { |entry| entry.outcome == state } }
            Chart::Series.new(label: I18n.t("home.healthcare.appointments.outcomes.#{state}"), values: values, color: color)
          end,
        )
      end

      # The next few visits from today, whatever period is selected.
      def upcoming
        future = Period.new(start_date: @today, end_date: @today + UPCOMING_HORIZON_DAYS)
        entries = self.class.visits(@window, future, today: @today)
          .entries.select(&:to_come?)
          .first(UPCOMING_LIMIT)

        entries.map do |entry|
          Upcoming.new(date: entry.date, title: entry.label, counterpart: entry.details.counterpart.presence, occurrence: entry.occurrence)
        end
      end

      # Attendance per provider (the day's counterpart), most visited first.
      def counterpart_rows
        ledger.entries.select(&:due?)
          .group_by { |entry| entry.details.counterpart.presence }
          .map do |counterpart, entries|
            CounterpartRow.new(counterpart: counterpart, due: entries.size, attended: entries.count(&:taken?), rate: OccurrenceLedger.rate(entries))
          end
          .sort_by { |row| -row.due }
      end

      private

      def ledger
        @ledger ||= self.class.visits(@window, @period, today: @today)
      end

      def previous_ledger
        @previous_ledger ||= self.class.visits(@window, @period.previous, today: @today)
      end
    end
  end
end
