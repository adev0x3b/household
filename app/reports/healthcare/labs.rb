# frozen_string_literal: true

module Reports
  module Healthcare
    # A lab result's values for a period, by the day they were measured on (the
    # LabTestResult day — an Occurrence — that holds them). Only results
    # that were actually done count: completed days, plus pending ones that
    # already hold values (people often type the values in without ticking
    # the result off); cancelled and skipped days don't.
    #
    #   out of range = entries flagged :low, :high or :abnormal (:abnormal
    #                  means past a critical bound, see LabTestResultEntry#flag)
    class Labs
      OUT_OF_RANGE_FLAGS = %i[low high abnormal].freeze
      # How long a critical value stays on the attention list.
      CRITICAL_DAYS = 90

      Reading = Data.define(:date, :value, :numeric, :flag)
      AnalyteRow = Data.define(:analyte, :unit, :latest, :readings) do
        def out_of_range_count = readings.count { |reading| OUT_OF_RANGE_FLAGS.include?(reading.flag) }
        def trend = readings.filter_map(&:numeric)
      end

      def initialize(audience:, period:, today: Date.current)
        @audience = audience
        @period = period
        @today = today
      end

      def any? = readings_for(@period).any?

      def out_of_range_metric
        Metric.new(
          value: out_of_range(readings_for(@period)).size, previous: out_of_range(readings_for(@period.previous)).size,
          format: :count, polarity: :lower_is_better, series: bucket_series,
        )
      end

      def critical_count = readings_for(@period).count { |entry| flag_for(entry) == :abnormal }

      # One row per analyte+unit (values in different units aren't
      # comparable), flagged analytes first, then alphabetical.
      def analyte_rows
        readings_for(@period)
          .group_by { |entry| [ entry.analyte, entry.unit ] }
          .map do |(analyte, unit), entries|
            readings = entries.sort_by { |entry| entry.occurrence.date }.map { |entry| reading(entry) }
            AnalyteRow.new(analyte: analyte, unit: unit, latest: readings.last, readings: readings)
          end
          .sort_by { |row| [ OUT_OF_RANGE_FLAGS.include?(row.latest.flag) ? 0 : 1, row.analyte.name.downcase ] }
      end

      # Critical values of the last 90 days, for the attention list.
      def critical_readings
        recent = Period.new(start_date: @today - CRITICAL_DAYS, end_date: @today)
        readings_for(recent).select { |entry| flag_for(entry) == :abnormal }.map { |entry| [ entry, reading(entry) ] }
      end

      private

      def readings_for(period)
        @readings ||= {}
        @readings[period] ||= entries.select { |entry| period.range.cover?(entry.occurrence.date) }
      end

      # Every value the report reads — the period, the one before it, the
      # critical values' last 90 days — loaded in one go.
      def entries
        @entries ||= LabTestResultEntry
          .joins(:occurrence)
          .where(occurrences: { event_id: @audience.events.of_type(LabTestResult).select(:id), date: span })
          .where.not(occurrences: { status: Occurrence.statuses.values_at("cancelled", "skipped") })
          .preload(:analyte, :unit, occurrence: { event: :profile })
          .to_a
          .tap { |entries| LabTestResultEntry.preload_reference_ranges(entries) }
      end

      def span = [ @period.previous.start_date, @today - CRITICAL_DAYS ].min..[ @period.end_date, @today ].max

      def out_of_range(entries) = entries.select { |entry| OUT_OF_RANGE_FLAGS.include?(flag_for(entry)) }

      def flag_for(entry)
        @flags ||= {}
        return @flags[entry.id] if @flags.key?(entry.id)

        @flags[entry.id] = entry.flag
      end

      def reading(entry)
        Reading.new(
          date: entry.occurrence.date, value: entry.value,
          numeric: entry.numeric_value, flag: flag_for(entry),
        )
      end

      def bucket_series
        @period.per_bucket(out_of_range(readings_for(@period))) { |entry| entry.occurrence.date }.map(&:size)
      end
    end
  end
end
