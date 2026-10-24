# frozen_string_literal: true

module Reports
  module Finance
    # What the household received over a period: the completed days the
    # viewer reads as income, which includes a housemate's expense logged
    # against the viewer.
    #
    # Every income category is common enough to keep a colour of its own
    # on the chart, unlike the expense categories Spending folds together.
    class Income
      CATEGORY_SERIES = {
        "salary" => "series-1",
        "freelance" => "series-2",
        "bonus" => "series-3",
        "refund" => "series-4",
        nil => "neutral"
      }.freeze

      def initialize(audience:, period:, window: Window.new(audience))
        @period = period
        @received = MoneyFlow.new(
          window.transaction_days, period: period, kind: :income, fallback_currency: audience.currency,
        )
      end

      delegate :any?, :other_currencies, to: :@received

      def primary_currency = @received.currency

      def total_metric = @received.metric(polarity: :neutral)

      def by_category_chart
        CategoryChart.new(
          period: @period, totals: @received.sum_by(:category, :date), colors: CATEGORY_SERIES,
          currency: primary_currency, title: I18n.t("home.finance.income.by_category_chart"),
        ) { |category| category_label(category) }.to_chart
      end

      def category_rows
        totals = @received.sum_by(:category).to_h { |category, cents| [ category_label(category), cents ] }
        AmountShare.of(totals, currency: primary_currency)
      end

      private

      def category_label(category)
        category ? I18n.t("transactions.category.#{category}") : I18n.t("home.finance.income.other")
      end
    end
  end
end
