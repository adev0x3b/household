# frozen_string_literal: true

module Reports
  class TransactionDays
    # The completed Transaction days of a span summed by date, kind (as the
    # viewer reads it), category and currency: one query, from which every
    # money metric on a page is added up in memory. A household's
    # months are a few hundred such rows.
    #
    #   totals = days.totals(during: period.range, kind: :expense)   # TransactionDays#totals
    #   totals.by_currency                                           # => [Money], largest first
    #   totals.where(currency: "EUR").sum_by(:category, :date)       # => { [category, date] => signed cents }
    class Totals
      Row = Data.define(:date, :kind, :category, :currency, :cents, :volume)

      # `days`' completed days in `span`, grouped.
      def self.load(days, span)
        groups = [ TransactionDays.date, days.kind, TransactionDays.category, TransactionDays.currency ]
        volume = Arel::Nodes::NamedFunction.new("ABS", [ days.amount ])
        rows = days.scope(during: span).group(*groups).pluck(*groups, Arel::Nodes::Sum.new([ days.amount ]), Arel::Nodes::Sum.new([ volume ]))
        new(rows.map do |date, kind, category, currency, cents, magnitude|
          Row.new(
            date: date, kind: Transaction::Details.kinds.key(kind), category: TransactionDays.category_name(category),
            currency: currency, cents: cents.to_i, volume: magnitude.to_i,
          )
        end)
      end

      def initialize(rows)
        @rows = rows
      end

      # The rows the filters keep: `during` (a date range), `kind` (:income /
      # :expense), `category` (one or several), `currency`.
      def where(during: nil, kind: nil, category: nil, currency: nil)
        categories = Array(category).map(&:to_s) if category
        self.class.new(@rows.select do |row|
          (during.nil? || during.cover?(row.date)) && (kind.nil? || row.kind == kind.to_s) &&
            (categories.nil? || categories.include?(row.category)) && (currency.nil? || row.currency == currency)
        end)
      end

      def any? = @rows.any?

      # Signed cents (negative: money out).
      def sum = @rows.sum(&:cents)

      # [Money] per currency, largest first (magnitudes).
      def by_currency
        @rows.group_by(&:currency)
          .map { |currency, rows| Money.new(cents: rows.sum(&:cents).abs, currency: currency) }
          .sort_by { |money| [ -money.cents, money.currency ] }
      end

      # { value => signed cents } by one of the rows' fields (:date,
      # :category, :kind, :currency), { [values] => signed cents } by several.
      def sum_by(*fields)
        @rows.group_by { |row| fields.one? ? row.public_send(fields.first) : fields.map { row.public_send(_1) } }
          .transform_values { |rows| rows.sum(&:cents) }
      end

      # The currencies by how much moved in each (in or out), largest first.
      def currencies_by_volume
        @rows.group_by(&:currency).transform_values { |rows| rows.sum(&:volume) }
          .sort_by { |currency, cents| [ -cents, currency ] }.map(&:first)
      end
    end
  end
end
