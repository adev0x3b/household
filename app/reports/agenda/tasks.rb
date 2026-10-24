# frozen_string_literal: true

module Reports
  module Agenda
    # The Agenda's tasks: how many of those planned got done and which were
    # not, each day from one OccurrenceLedger, so a past day with no row is
    # simply not done. "Due today" and the two lists (coming up, overdue in
    # the last 30 days) are as of today, whatever period is selected.
    class Tasks
      Row = Data.define(:date, :title, :priority, :occurrence)
      SeriesRow = Data.define(:name, :due, :done, :rate, :next_date)
      PriorityRow = Data.define(:priority, :due, :done, :rate)

      def initialize(period:, today:, window:)
        @period = period
        @today = today
        @window = window
      end

      def any? = entries_in(@period).any?

      def completion_metric
        Metric.new(value: rate(@period), previous: rate(@period.previous), format: :percent, polarity: :higher_is_better)
      end

      def overdue_metric
        Metric.new(
          value: overdue_in(@period).size, previous: overdue_in(@period.previous).size,
          format: :count, polarity: :lower_is_better,
        )
      end

      def due_today_metric
        Metric.new(value: entries_in(today_only).count(&:due_today?), format: :count, polarity: :neutral)
      end

      # Today's tasks: how many are done, out of how many (cancelled ones aside).
      def today_progress
        todays = entries_in(today_only).reject(&:cancelled?)
        { done: todays.count { |entry| entry.taken? || entry.skipped? }, total: todays.size }
      end

      # Overdue in the last 30 days. Most important first, then oldest first.
      def overdue_rows
        overdue_in(Period.recent(today: @today)).map { |entry| row(entry) }.sort_by { |row| [ -rank(row.priority), row.date ] }
      end

      # Today's open tasks and the next 7 days, by day, most important first.
      def upcoming_rows
        entries_in(Period.from_today(today: @today))
          .select(&:to_come?)
          .map { |entry| row(entry) }
          .sort_by { |row| [ row.date, -rank(row.priority) ] }
      end

      # Done vs not done per bucket of the period. Only tasks whose day has
      # passed count, so buckets still to come stay empty.
      def progress_chart
        due = @period.per_bucket(entries_in(@period).select(&:due?), &:date)
        done = due.map { |entries| entries.count(&:taken?) }
        not_done = due.map { |entries| entries.count { |entry| !entry.taken? } }

        Chart.new(
          kind: :stacked_bar, title: I18n.t("home.agenda.progress.chart"),
          labels: @period.bucket_labels,
          series: [
            Chart::Series.new(label: I18n.t("home.agenda.progress.done"), values: done, color: "good"),
            Chart::Series.new(label: I18n.t("home.agenda.progress.not_done"), values: not_done, color: "critical")
          ],
        )
      end

      # One row per task (a repeating task is one row), the ones we keep up
      # with least first.
      def series_rows
        entries_in(@period).group_by(&:event).filter_map do |event, entries|
          due = entries.select(&:due?)
          next if due.empty?

          SeriesRow.new(
            name: event.event_label, due: due.size, done: due.count(&:taken?),
            rate: OccurrenceLedger.rate(entries), next_date: next_date(event),
          )
        end.sort_by { |row| [ row.rate, row.name.to_s ] }
      end

      def timed? = timing.any?

      # How early or late the period's tasks were done against their day.
      def timing_chart = timing.to_chart

      # Completion by priority, the most important first.
      def priority_rows
        entries_in(@period).select(&:due?).group_by { |entry| entry.details.priority }.map do |priority, entries|
          PriorityRow.new(
            priority: priority, due: entries.size, done: entries.count(&:taken?), rate: OccurrenceLedger.rate(entries),
          )
        end.sort_by { |row| -rank(row.priority) }
      end

      private

      def today_only = Period.new(start_date: @today, end_date: @today)

      # One ledger for everything this report shows: an entry's state
      # depends only on its date and today, so any span is a slice of it.
      def entries
        @entries ||= begin
          span = Period.new(
            start_date: [ @period.previous.start_date, Period.recent(today: @today).start_date ].min,
            end_date: [ @period.end_date, Period.ahead(today: @today).end_date ].max,
          )
          @window.ledger(span, today: @today, of: Task).entries
        end
      end

      def entries_in(period) = entries.select { |entry| period.range.cover?(entry.date) }

      def rate(period) = OccurrenceLedger.rate(entries_in(period))

      def overdue_in(period) = entries_in(period).select(&:missed?)

      def timing
        @timing ||= TimingChart.new(
          entries_in(@period),
          title: I18n.t("home.agenda.timing.chart"), series_label: I18n.t("home.agenda.timing.tasks"),
        )
      end

      # A priority's place in the order of importance; a day with none
      # ranks as a normal one.
      def rank(priority) = Task::Details.priorities.fetch(priority.to_s, Event::DEFAULT_PRIORITY_RANK)

      def next_date(event)
        entries.find { |entry| entry.event == event && entry.to_come? }&.date
      end

      # The day's own priority and title when they were changed for that
      # day, else the series'.
      def row(entry)
        Row.new(date: entry.date, title: entry.label, priority: entry.details.priority, occurrence: entry.occurrence)
      end
    end
  end
end
