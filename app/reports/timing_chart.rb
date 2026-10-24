# frozen_string_literal: true

module Reports
  # How early or late things were done against their planned day: one bar
  # per day of difference, from CLAMP days late to CLAMP days early, the
  # bars at either end gathering everything further out so that one task
  # done a month late doesn't stretch the axis. On time is drawn "good" and
  # both tails in one hue, because the bars are an ordered distribution,
  # not categories.
  class TimingChart
    CLAMP = 3
    OFFSETS = (-CLAMP..CLAMP)

    # `entries` are OccurrenceLedger entries; the taken ones whose
    # completion day is known are counted.
    def initialize(entries, title:, series_label:)
      @offsets = entries.select(&:taken?).filter_map(&:days_offset)
      @title = title
      @series_label = series_label
    end

    def any? = @offsets.any?

    def to_chart
      Chart.new(
        kind: :bar, title: @title, labels: OFFSETS.map { |offset| label(offset) },
        series: [
          Chart::Series.new(
            label: @series_label, values: counts, colors: OFFSETS.map { |offset| offset.zero? ? "good" : "series-1" },
          )
        ],
      )
    end

    private

    def counts
      tally = @offsets.map { |offset| offset.clamp(-CLAMP, CLAMP) }.tally
      OFFSETS.map { |offset| tally.fetch(offset, 0) }
    end

    # Days early are positive, days late negative (Occurrence#days_offset).
    def label(offset)
      text =
        if offset.zero? then I18n.t("statistics.timing.on_time")
        elsif offset.positive? then I18n.t("statistics.timing.early", count: offset)
        else I18n.t("statistics.timing.late", count: -offset)
        end
      offset.abs == CLAMP ? "#{text}+" : text
    end
  end
end
