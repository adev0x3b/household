# frozen_string_literal: true

module Reports
  module Finance
    # The two figures that need income and expenses together, so neither
    # Spending nor Income owns them.
    #
    # Net cash flow is the completed days' amounts summed as the viewer
    # reads them: positive for income, negative for an expense. A payment
    # between housemates is one person's expense and the other's income, so
    # summing the signed amounts nets it out from each side. A transfer to
    # savings is left out, as money the household still has
    # (Transaction::Details.cash_categories). This is the one figure whose
    # Money keeps its sign, since "net" can be negative.
    #
    # The savings rate is what went to the savings category over what came
    # in, against the usual rule of thumb of saving a fifth of one's income.
    class CashFlow
      TARGET_SAVINGS_RATE = 20

      def initialize(audience:, period:, window: Window.new(audience))
        @period = period
        @days = window.transaction_days
        @net = MoneyFlow.new(@days, period: period, category: Transaction::Details.cash_categories, fallback_currency: audience.currency)
      end

      def net_cash_flow_metric = @net.metric(polarity: :higher_is_better)

      def savings_rate_metric
        Metric.new(
          value: savings_rate(@period), previous: savings_rate(@period.previous), format: :percent,
          polarity: :higher_is_better, target: TARGET_SAVINGS_RATE,
        )
      end

      private

      def savings_rate(period)
        income = completed(period, kind: :income).sum
        return nil if income.zero?

        saved = completed(period, kind: :expense, category: :savings).sum.abs
        (saved * 100.0 / income).round(1)
      end

      def completed(period, **filters) = @days.totals(during: period.range, currency: @net.currency, **filters)
    end
  end
end
