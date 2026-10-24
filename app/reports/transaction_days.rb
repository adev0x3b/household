# frozen_string_literal: true

module Reports
  # The Transaction days an audience can read, in SQL, as its viewer reads
  # them. Every money report (Finance, Healthcare spending, groceries)
  # builds on it, so that:
  #
  # * a sum never meets the share tables (scoped through audience.event_ids);
  # * every field is the day's own value, else its series' (an override row
  #   carries only what differs, Occurrence.resolved_sql);
  # * a payment between housemates — one series, two readers — is read from
  #   the viewer's side: the owner's expense is the counterparty's income
  #   and its amount is negated for them (Transaction.viewer_amount_sql /
  #   viewer_kind_sql). An amount is stored without a sign, so sum #amount,
  #   never the column: summed bare it loses which way the money went.
  #
  #   days = TransactionDays.new(audience)
  #   days.totals(during: period.range, kind: :expense, category: :groceries).by_currency   # => [Money], largest first
  #   spent = days.scope(during: period.range, kind: :expense, category: :groceries)
  #   days.sum_by(spent, TransactionDays.date)              # => { date => signed cents }
  #
  # The metrics read #totals: the completed days of the span the page covers
  # summed in one query (Totals), then added up in memory. A breakdown that
  # needs more than a day's date, kind, category and currency (what it paid
  # for, a list of days) queries #scope.
  #
  # Money is only what was done: `status:` defaults to completed (pending,
  # cancelled and skipped days are not money spent or received).
  #
  # Every expression is an Arel node (Arel.sql), compared with Arel's
  # predicates (`eq`, `in`, `not_eq`), so no query builds SQL from strings
  # at its call site and every value is bound or quoted.
  class TransactionDays
    class << self
      def date = Occurrence.arel_table[:date]
      def currency = Arel.sql(Occurrence.resolved_sql(:currency, type: Transaction))
      def category = Arel.sql(Occurrence.resolved_sql(:category, type: Transaction))

      # The amount signed as its owner reads it (negative: expense), whoever
      # is looking — for what is owed between the two of them.
      def owner_amount = Arel.sql(Transaction.owner_amount_sql)

      # What a day's own row or, failing that, its series' row says it pays
      # for (polymorphic: Event, Occurrence, SupplyPurchase, IngredientPurchase).
      def about_type = Arel.sql("COALESCE(transaction_details_own.about_type, transaction_details_series.about_type)")

      def about_id
        Arel.sql("CASE WHEN transaction_details_own.about_type IS NOT NULL THEN transaction_details_own.about_id " \
                 "ELSE transaction_details_series.about_id END")
      end

      # The kind of thing paid for, after #with_about: the host series' type
      # (a day or a series of it), else the purchase's class; NULL for a
      # cost about nothing.
      def about_kind
        Arel.sql("COALESCE(about_events.type, transaction_details_own.about_type, transaction_details_series.about_type)")
      end

      # The collection the thing paid for belongs to, after #with_about: the
      # host series' collection, or a supply purchase's.
      def about_collection = Arel.sql("COALESCE(about_events.collection_id, about_supply_purchases.collection_id)")

      # The joins #with_about adds: the day paid for, its series (or the
      # series paid for), the supply purchase paid for.
      def about_joins
        [
          "LEFT JOIN occurrences about_occurrences ON #{about_type} = 'Occurrence' AND about_occurrences.id = #{about_id}",
          "LEFT JOIN events about_events ON about_events.id = CASE #{about_type} " \
          "WHEN 'Occurrence' THEN about_occurrences.event_id WHEN 'Event' THEN #{about_id} END",
          "LEFT JOIN supply_purchases about_supply_purchases ON #{about_type} = 'SupplyPurchase' AND about_supply_purchases.id = #{about_id}"
        ]
      end

      def categories(names) = Array(names).map { |name| Transaction::Details.categories.fetch(name.to_s) }
      def category_name(value) = Transaction::Details.categories.key(value)
    end

    def initialize(audience, events: audience.event_ids)
      @viewer = audience.viewer
      @event_ids = events
    end

    # Widens the span #totals will load (a date range), so the reports' own
    # asks fall inside it. Loads nothing yet.
    def cover(range)
      widen(range)
      self
    end

    # The completed days' sums between the dates of `during`, filtered as
    # #scope's are (`kind`, `category`, `currency`): read from one load of
    # the covered span, which a range outside it widens (one load more).
    def totals(during:, **filters)
      widen(during)
      @totals ||= Totals.load(self, @span)
      @totals.where(during: during, **filters)
    end

    # Signed cents as the viewer reads them (negative: money out).
    def amount = Arel.sql(Transaction.viewer_amount_sql(@viewer))

    # 0 income / 1 expense, as the viewer reads it.
    def kind = Arel.sql(Transaction.viewer_kind_sql(@viewer))

    # The days, filtered: `status` (nil for any), `during` (a date range),
    # `kind` (:income / :expense, the viewer's side), `category` (one or
    # several), `currency`.
    def scope(status: :completed, during: nil, kind: nil, category: nil, currency: nil)
      relation = Occurrence.of_type(Transaction).with_series(Transaction).where(event_id: @event_ids)
      relation = relation.where(status: status) if status
      relation = relation.where(date: during) if during
      relation = relation.where(self.kind.eq(Transaction::Details.kinds.fetch(kind.to_s))) if kind
      relation = relation.where(self.class.category.in(self.class.categories(category))) if category
      relation = relation.where(self.class.currency.eq(currency)) if currency
      relation
    end

    # Joins what each day pays for (see .about_kind, .about_collection).
    def with_about(relation) = relation.joins(*self.class.about_joins)

    # Signed cents (an Integer: Postgres sums bigints as numeric).
    def sum(relation) = relation.sum(amount).to_i

    # { group value(s) => signed cents }, grouped by expressions (Arel
    # nodes, or plain column names).
    def sum_by(relation, *groups) = relation.group(*groups).sum(amount).transform_values(&:to_i)

    private

    def widen(range)
      return if @span&.cover?(range.begin) && @span.cover?(range.end)

      @span = @span ? [ @span.begin, range.begin ].min..[ @span.end, range.end ].max : range
      @totals = nil
    end
  end
end
