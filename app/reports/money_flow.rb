# frozen_string_literal: true

module Reports
  # Money that moved over a period as the viewer reads it: what was spent,
  # what was received, or, with no kind, the net of both. A flow is shown
  # in one currency, the one most money moved in, and the others are listed
  # beside it, never added in.
  #
  #   spent = MoneyFlow.new(window.transaction_days, period:, kind: :expense, fallback_currency: audience.currency)
  #   spent.total                        # => Money, in spent.currency
  #   spent.metric(polarity: :neutral)   # => Metric, against the period before, with a point per bucket
  class MoneyFlow
    # `days` is the page's TransactionDays; `kind` and `category` narrow the
    # flow as TransactionDays#totals does. `fallback_currency` is what a
    # flow with nothing in it is shown in.
    def initialize(days, period:, fallback_currency:, kind: nil, category: nil)
      @days = days
      @period = period
      @fallback_currency = fallback_currency
      @filters = { kind: kind, category: category }.compact
    end

    def any? = totals(@period).any?

    # The currency most money moved in during the period, else during the
    # period before, else the household's.
    def currency
      @currency ||= totals(@period).currencies_by_volume.first ||
                    totals(@period.previous).currencies_by_volume.first ||
                    @fallback_currency
    end

    # What moved in every other currency, largest first.
    def other_currencies
      totals(@period).by_currency.reject { |money| money.currency == currency }
    end

    # A flow of one kind is a magnitude, since spent or received already
    # says which way the money went. The net of both kinds keeps its sign.
    def total(period = @period) = money(net_cents(totals(period, currency: currency).sum))

    # The flow's sums in its currency over the period, grouped as
    # TransactionDays::Totals#sum_by groups them.
    def sum_by(*fields) = totals(@period, currency: currency).sum_by(*fields)

    # The total of each bucket of the period, in units of the currency, for
    # a chart's points.
    def bucket_amounts
      @period.per_bucket(sum_by(:date)) { |date, _cents| date }.map do |sums|
        money(net_cents(sums.sum { |_date, cents| cents })).to_f
      end
    end

    def metric(polarity:)
      Metric.new(
        value: total, previous: total(@period.previous), format: :money, polarity: polarity, series: bucket_amounts,
      )
    end

    private

    def totals(period, **filters) = @days.totals(during: period.range, **@filters, **filters)

    def net_cents(cents) = @filters.key?(:kind) ? cents.abs : cents

    def money(cents) = Money.new(cents: cents, currency: currency)
  end
end
