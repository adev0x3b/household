# frozen_string_literal: true

module Reports
  module Healthcare
    # What healthcare cost over a period: the completed days in the
    # healthcare category that the viewer reads as an expense. "Scheduled"
    # is what is still expected from today to the end of the period: the
    # pending days, and the days of repeating series nothing was saved
    # about yet, priced from their series.
    #
    # What the money went towards is what each day pays for: its own
    # details' `about`, else its series'. That is a visit, a dose or a lab
    # test (by the kind of series it belongs to), or a supply purchase.
    # Cost per therapy follows the same thing to its collection.
    class Spending
      TOP_SUPPLIES_LIMIT = 5

      # Keyed by what was paid for (the type name the days' rows carry), so
      # that a kind keeps its colour however the rows are sorted or filtered.
      TYPE_SERIES = {
        Appointment.name => "series-1",
        Medication.name => "series-2",
        SupplyPurchase.name => "series-3",
        LabTestResult.name => "series-4",
        nil => "neutral"
      }.freeze

      def initialize(audience:, period:, today: Date.current, window: Window.new(audience))
        @viewer = audience.viewer
        @period = period
        @today = today
        @window = window
        @days = window.transaction_days
        @spent = MoneyFlow.new(
          @days, period: period, kind: :expense, category: :healthcare, fallback_currency: audience.currency,
        )
      end

      delegate :any?, :other_currencies, to: :@spent

      def primary_currency = @spent.currency

      def spend_metric = @spent.metric(polarity: :neutral)

      def scheduled
        return Money.zero(primary_currency) if @today > @period.end_date

        pending = @days.sum(expenses(status: :pending, during: remaining_days)).abs
        Money.new(cents: pending + projected_cents, currency: primary_currency)
      end

      def by_type_chart
        totals = @days.sum_by(@days.with_about(in_period), TransactionDays.about_kind, TransactionDays.date)
        CategoryChart.new(
          period: @period, totals: totals, colors: TYPE_SERIES, currency: primary_currency,
          title: I18n.t("home.healthcare.spending.by_type_chart"),
        ) { |type| type_label(type) }.to_chart
      end

      # Cost per collection (a therapy, in Healthcare's words): what each
      # day paid for, followed to the collection of its series or purchase.
      def collection_rows
        collection = TransactionDays.about_collection
        totals = @days.sum_by(@days.with_about(in_period).where(collection.not_eq(nil)), collection)
        return [] if totals.empty?

        names = Collection.where(id: totals.keys).pluck(:id, :name).to_h
        AmountShare.of(totals.to_h { |id, cents| [ names[id], cents.abs ] }, currency: primary_currency)
      end

      def top_supply_rows
        purchases = @days.with_about(in_period).where(TransactionDays.about_type.eq("SupplyPurchase"))
          .joins("INNER JOIN supplies ON supplies.id = about_supply_purchases.supply_id")
        totals = @days.sum_by(purchases, Supply.arel_table[:name]).transform_values(&:abs)

        AmountShare.of(totals, currency: primary_currency).first(TOP_SUPPLIES_LIMIT)
      end

      private

      # The days themselves, in the flow's currency, for what a sum by date
      # and category can't say: what they paid for, what is still pending.
      def expenses(**filters)
        @days.scope(kind: :expense, category: :healthcare, currency: primary_currency, **filters)
      end

      def in_period = expenses(during: @period.range)

      def remaining_days = [ @today, @period.start_date ].max..@period.end_date

      # The days of repeating healthcare expenses still to come in the
      # period with nothing saved yet, each priced from its series as the
      # viewer reads it.
      def projected_cents
        from, to = remaining_days.begin, remaining_days.end
        @window.events(from, to, of: Transaction).sum do |event|
          details = event.details
          next 0 unless event.recurring? && details.category == "healthcare" && details.currency == primary_currency
          next 0 unless event.kind_for(@viewer) == "expense"

          event.occurrences_between(from, to).count(&:projected?) * details.amount_cents
        end
      end

      def type_label(type)
        type ? type.constantize.model_name.human : I18n.t("home.healthcare.spending.other")
      end
    end
  end
end
