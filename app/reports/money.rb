# frozen_string_literal: true

module Reports
  # An aggregate amount in a single currency. Dashboards never add cents
  # across currencies: sums are grouped by currency first
  # (TransactionDays::Totals#by_currency) and each group is shown on its
  # own. Always stored as a positive magnitude, since the sign of a sum is
  # carried by what the metric measures ("spent", "earned"), not by the
  # number.
  class Money < Data.define(:cents, :currency)
    include Comparable

    def self.zero(currency) = new(cents: 0, currency: currency)

    def +(other) = with_same_currency(other) { new_cents(cents + other.cents) }
    def -(other) = with_same_currency(other) { new_cents(cents - other.cents) }

    def <=>(other)
      return nil unless other.is_a?(Money) && other.currency == currency

      cents <=> other.cents
    end

    def zero? = cents.zero?
    def positive? = cents.positive?
    def negative? = cents.negative?
    def abs = new_cents(cents.abs)

    def amount = BigDecimal(cents.to_s) / Transaction::CURRENCY_SCALE

    def to_f = amount.to_f

    # With the decimals its currency has: "€1,234.56", "¥1,200".
    def to_s
      unit = Currency.new(currency)
      ActiveSupport::NumberHelper.number_to_currency(amount, unit: unit.symbol, precision: unit.decimals, locale: I18n.locale)
    end

    private

    def new_cents(value) = self.class.new(cents: value, currency: currency)

    def with_same_currency(other)
      raise ArgumentError, "cannot combine #{currency} with #{other.currency}" unless other.currency == currency

      yield
    end
  end
end
