# frozen_string_literal: true

module Reports
  module Finance
    # What the household spent over a period, in every category but
    # savings: the completed days the viewer reads as an expense. A
    # payment a housemate logged against the viewer is the viewer's income,
    # so it never counts here (TransactionDays reads every day from the
    # viewer's side), and a transfer to savings is money kept, not spent
    # (Transaction::Details.cash_categories).
    #
    # Only the four categories nearly every household budget has keep a
    # colour of their own on the chart; the rest are drawn together as
    # "Other" and still count in the total and in the table.
    class Spending
      TOP_TRANSACTIONS_LIMIT = 10

      CATEGORY_SERIES = {
        "housing" => "series-1",
        "groceries" => "series-2",
        "transportation" => "series-3",
        "healthcare" => "series-4",
        nil => "neutral"
      }.freeze

      TransactionRow = Data.define(:date, :title, :category, :money, :occurrence)

      def initialize(audience:, period:, window: Window.new(audience))
        @period = period
        @days = window.transaction_days
        @spent = MoneyFlow.new(@days, period: period, kind: :expense, category: Transaction::Details.cash_categories,
                                      fallback_currency: audience.currency)
      end

      delegate :any?, :other_currencies, to: :@spent

      def primary_currency = @spent.currency

      def total_metric = @spent.metric(polarity: :neutral)

      def by_category_chart
        CategoryChart.new(
          period: @period, totals: @spent.sum_by(:category, :date), colors: CATEGORY_SERIES, currency: primary_currency,
          title: I18n.t("home.finance.spending.by_category_chart"),
        ) { |category| category_label(category) }.to_chart
      end

      def category_rows
        totals = @spent.sum_by(:category).to_h { |category, cents| [ category_label(category), cents.abs ] }
        AmountShare.of(totals, currency: primary_currency)
      end

      # The largest expenses of the period, each a day the page can open.
      def top_transaction_rows
        largest_expenses.map do |day|
          TransactionRow.new(
            date: day.date, title: day.event_label,
            category: category_label(TransactionDays.category_name(day.resolved_category)),
            money: Money.new(cents: day.viewer_amount_cents.to_i.abs, currency: primary_currency), occurrence: day,
          )
        end
      end

      private

      def largest_expenses
        @days.scope(during: @period.range, kind: :expense, category: Transaction::Details.cash_categories, currency: primary_currency)
          .select(
            Occurrence.arel_table[Arel.star],
            @days.amount.as("viewer_amount_cents"),
            TransactionDays.category.as("resolved_category"),
          )
          .order(@days.amount.asc, :date, :id).limit(TOP_TRANSACTIONS_LIMIT)
          .preload(:event)
      end

      def category_label(category)
        category ? I18n.t("transactions.category.#{category}") : I18n.t("home.finance.spending.other")
      end
    end
  end
end
