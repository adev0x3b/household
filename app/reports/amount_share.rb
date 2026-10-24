# frozen_string_literal: true

module Reports
  # One part of a total, as a breakdown table lists it: what it is, how
  # much, and its share of the whole in whole percent.
  class AmountShare < Data.define(:label, :money, :share)
    # `totals` maps each part's label to its cents in `currency`. The parts
    # come largest first.
    def self.of(totals, currency:)
      whole = totals.values.sum
      parts = totals.map do |label, cents|
        share = whole.zero? ? 0 : (cents * 100.0 / whole).round
        new(label: label, money: Money.new(cents: cents, currency: currency), share: share)
      end
      parts.sort_by { |part| -part.money.cents }
    end
  end
end
