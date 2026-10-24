# frozen_string_literal: true

module Reports
  module Healthcare
    # Dose adherence for a period, from an OccurrenceLedger over the
    # audience's Medication series (each dose of a day is its own entry).
    #
    #   adherence = taken ÷ due (due = taken + skipped + missed; cancelled
    #               and not-yet-due doses are excluded). Target 80%, the
    #               usual threshold for "adherent" (PDC ≥ 80%).
    #   missed    = missed + skipped
    #   timing    = days between the scheduled and the actual date, for
    #               taken doses whose completion time is known
    class Medications
      TARGET = 80
      # How many scheduled dates past the period are looked at for the next dose.
      NEXT_LOOKAHEAD = 10

      Row = Data.define(:event, :name, :due, :taken, :rate, :streak, :next_date)

      def initialize(audience:, period:, today: Date.current, window: Window.new(audience))
        @period = period
        @today = today
        @window = window
      end

      def adherence_metric
        Metric.new(
          value: ledger.rate, previous: previous_ledger.rate, format: :percent,
          polarity: :higher_is_better, target: TARGET, series: adherence_by_bucket,
        )
      end

      def missed_metric
        Metric.new(
          value: missed_count(ledger.entries), previous: missed_count(previous_ledger.entries), format: :count,
          polarity: :lower_is_better, series: bucket_series { |entries| missed_count(entries) },
        )
      end

      def any? = ledger.entries.any?

      def adherence_chart
        Chart.new(
          kind: :line, title: I18n.t("home.healthcare.medications.adherence_chart"),
          labels: @period.bucket_labels, format: :percent, target: TARGET,
          series: [
            Chart::Series.new(label: I18n.t("home.healthcare.kpis.adherence"), values: adherence_by_bucket)
          ],
        )
      end

      # How early or late the period's doses were taken against their day.
      def timing_chart
        TimingChart.new(
          ledger.entries,
          title: I18n.t("home.healthcare.medications.timing_chart"),
          series_label: I18n.t("home.healthcare.medications.doses"),
        ).to_chart
      end

      # One row per medication (a series), the least kept up with first.
      def rows
        ledger.by_event.map do |event, entries|
          Row.new(
            event: event, name: event.event_label, due: entries.count(&:due?), taken: entries.count(&:taken?),
            rate: OccurrenceLedger.rate(entries), streak: streak(entries), next_date: next_date(event, entries),
          )
        end.sort_by { |row| [ row.rate || Float::INFINITY, row.name.to_s ] }
      end

      private

      def ledger
        @ledger ||= @window.ledger(@period, today: @today, of: Medication)
      end

      def previous_ledger
        @previous_ledger ||= @window.ledger(@period.previous, today: @today, of: Medication)
      end

      def missed_count(entries) = entries.count { |entry| entry.missed? || entry.skipped? }

      def entries_by_bucket
        @entries_by_bucket ||= @period.per_bucket(ledger.entries, &:date)
      end

      # A value per bucket, nil for the buckets that haven't started yet so
      # that a line stops at today instead of dropping to zero.
      def bucket_series
        @period.buckets.zip(entries_by_bucket).map do |bucket, entries|
          bucket.start_date > @today ? nil : yield(entries)
        end
      end

      def adherence_by_bucket = bucket_series { |entries| OccurrenceLedger.rate(entries) }

      # Consecutive taken doses counting back from the most recent due one.
      def streak(entries)
        entries.select(&:due?).reverse.take_while(&:taken?).size
      end

      # The first dose still to come in the period, else the schedule's next
      # date after it (one deleted from the series is never next).
      def next_date(event, entries)
        to_come = entries.find(&:to_come?)
        return to_come.date if to_come
        return nil unless event.recurring?

        after = [ @today, @period.end_date ].max
        event.schedule.dates_after(after, NEXT_LOOKAHEAD).find { |date| !event.excluded_on?(date) }
      end
    end
  end
end
