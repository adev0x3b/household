# frozen_string_literal: true

module Reports
  # A library-neutral chart description. Views build one, and
  # Components::Statistics::Chart renders it twice: as JSON for
  # chart_controller.js (the only place that knows Chart.js) and as a
  # visually hidden <table> for screen readers. Colors are token names
  # (see COLOR_TOKENS), never hex, so the palette lives in SCSS only.
  #
  # Kinds:
  #   :line           change over time (one or more series, optional target line)
  #   :bar            magnitude per category or bucket
  #   :stacked_bar    composition per bucket (series stack)
  #   :horizontal_bar ranking; a series may color each bar via `colors:`
  #   :sparkline      a bare line inside a stat tile, with no axes or legend
  class Chart < Data.define(:kind, :labels, :series, :format, :currency, :target, :title)
    KINDS = %i[line bar stacked_bar horizontal_bar sparkline].freeze
    COLOR_TOKENS = %w[
      series-1 series-2 series-3 series-4 series-5 series-6
      good warning critical neutral
    ].freeze

    Series = Data.define(:label, :values, :color, :colors) do
      def initialize(label:, values:, color: "series-1", colors: nil) = super
    end

    def initialize(kind:, labels:, series:, title:, format: :count, currency: nil, target: nil)
      raise ArgumentError, "unknown chart kind #{kind}" unless KINDS.include?(kind)

      tokens = series.flat_map { |s| [ s.color, *s.colors ] }
      unknown = tokens - COLOR_TOKENS
      raise ArgumentError, "unknown color token(s) #{unknown.join(', ')}" if unknown.any?

      super
    end

    def empty? = series.all? { |s| s.values.compact.all?(&:zero?) }

    # One of its values as the figures format it: a money chart draws
    # amounts, which its table shows as Money in the chart's currency.
    def point(value)
      return value unless format == :money

      Money.new(cents: Transaction.amount_to_cents(value), currency: currency)
    end

    def to_spec
      {
        kind: kind,
        labels: labels,
        series: series.map { |s| { label: s.label, values: s.values, color: s.color, colors: s.colors }.compact },
        format: format,
        currency: currency,
        target: target,
        target_label: target && I18n.t("statistics.target_label"),
        locale: I18n.locale
      }.compact
    end
  end
end
