# frozen_string_literal: true

module Reports
  module Finance
    # Net balance between household members for a period, from the
    # payments logged against a housemate (a Transaction series whose
    # details name a `counterparty_profile`) — the app's answer to "who
    # owes whom".
    #
    # A payment between housemates is one fact with two readers: one series,
    # owned by whoever logged it, that its counterparty reads too
    # (Event.accessible_by). So each payment the viewer can read is counted
    # exactly once, whichever side they are on, and both of them see the
    # same balance — there is no mirror row to pair up or to dedupe.
    #
    # From the owner's side: an expense means the owner paid out on the
    # counterparty's behalf (the counterparty owes the owner); an income
    # logged against them means a settlement was received (reducing, or
    # reversing, what's owed). Both collapse to one formula: the
    # counterparty owes the owner −amount (the day's amount as the owner
    # reads it: negative for an expense, positive for an income).
    #
    # Deliberately ignores Audience's member filter: a balance is a
    # relationship between two profiles, not "one member's data". Only the
    # viewer's own accessibility scopes this report. It means something
    # only when Audience#shared?, and the Finance page shows it only then.
    class Settlements
      Balance = Data.define(:creditor, :debtor, :money)

      def initialize(audience:, period:)
        @audience = audience
        @period = period
      end

      def any? = balances.any?

      # [Balance], largest first: `debtor` owes `creditor` `money`.
      def balances
        @balances ||= net_by_pair_and_currency.filter_map do |(profile_a, profile_b, currency), cents|
          next if cents.zero?

          creditor, debtor = cents.positive? ? [ profile_a, profile_b ] : [ profile_b, profile_a ]
          Balance.new(creditor: creditor, debtor: debtor, money: Money.new(cents: cents.abs, currency: currency))
        end.sort_by { |balance| -balance.money.cents }
      end

      private

      # { [owner_id, counterparty_id, currency] => cents owed to the owner }:
      # every completed payment with a counterparty that the viewer can
      # read, once (scoped by a subquery of ids, never a join on shares),
      # at −its amount as the owner reads it.
      def owed_to_owners
        Occurrence.of_type(Transaction).with_series(Transaction)
          .where(event_id: Event.accessible_by(@audience.viewer).select(:id))
          .completed.where(date: @period.range)
          .where.not(transaction_details_series: { counterparty_profile_id: nil })
          .group("events.profile_id", "transaction_details_series.counterparty_profile_id", TransactionDays.currency)
          .sum(TransactionDays.owner_amount)
          .transform_values { |cents| -cents.to_i }
      end

      # { [profile_a, profile_b, currency] => net_cents }, profile_a/b
      # ordered by id so each pair accumulates under one key whichever of
      # them logged the payment. Positive means profile_a is owed by
      # profile_b.
      def net_by_pair_and_currency
        rows = owed_to_owners
        profiles = Profile.where(id: rows.keys.flat_map { |owner, counterparty, _| [ owner, counterparty ] }.uniq).index_by(&:id)

        rows.each_with_object(Hash.new(0)) do |((owner_id, counterparty_id, currency), cents), totals|
          owner, counterparty = profiles.values_at(owner_id, counterparty_id)
          profile_a, profile_b, sign = owner.id < counterparty.id ? [ owner, counterparty, 1 ] : [ counterparty, owner, -1 ]
          totals[[ profile_a, profile_b, currency ]] += cents * sign
        end
      end
    end
  end
end
