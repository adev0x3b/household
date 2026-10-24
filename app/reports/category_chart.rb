# frozen_string_literal: true

module Reports
  # Money per bucket of a period, stacked by category. Each category the
  # chart names keeps its own colour whatever else moved, so a reader learns
  # that housing is always the same blue. Everything else is gathered under
  # the category keyed nil, the "other" series, so a chart never has more
  # series than its palette can tell apart.
  #
  #   CategoryChart.new(
  #     period:, totals: flow.sum_by(:category, :date), colors: { "housing" => "series-1", nil => "neutral" },
  #     currency: flow.currency, title:,
  #   ) { |category| label }.to_chart
  class CategoryChart
    # `totals` maps [category, date] to cents; the block names a category
    # (nil for the other series).
    def initialize(period:, totals:, colors:, currency:, title:, &label)
      @period = period
      @totals = totals
      @colors = colors
      @currency = currency
      @title = title
      @label = label
    end

    def to_chart
      Chart.new(
        kind: :stacked_bar, title: @title, labels: @period.bucket_labels, format: :money, currency: @currency,
        series: series,
      )
    end

    private

    def series
      @colors.filter_map do |category, color|
        amounts = bucket_amounts(category)
        Chart::Series.new(label: @label.call(category), values: amounts, color: color) unless amounts.all?(&:zero?)
      end
    end

    def bucket_amounts(category)
      rows = @totals.select { |(row_category, _date), _cents| series_of(row_category) == category }
      @period.per_bucket(rows) { |(_category, date), _cents| date }.map do |sums|
        Money.new(cents: sums.sum { |_key, cents| cents.abs }, currency: @currency).to_f
      end
    end

    def series_of(category) = @colors.key?(category) ? category : nil
  end
end
