# frozen_string_literal: true

require "test_helper"

class Reports::Finance::SettlementsTest < ActiveSupport::TestCase
  setup do
    @payer = profiles(:alice)
    @counterparty = profiles(:bob)
    @march = period(Date.new(2025, 3, 1), Date.new(2025, 3, 31))
  end

  test "the counterparty owes the payer" do
    transfer!(payer: @payer, counterparty: @counterparty, date: Date.new(2025, 3, 2), cents: 100_00)

    balance = report(@payer).balances.sole

    assert_equal [ @counterparty, @payer, 100_00 ], [ balance.debtor, balance.creditor, balance.money.cents ]
  end

  # One payment, two readers: the counterparty reads the payer's own series
  # (Event.accessible_by), so both see the same balance from their side.
  test "both of them see the same balance" do
    transfer!(payer: @payer, counterparty: @counterparty, date: Date.new(2025, 3, 2), cents: 100_00)
    transfer!(payer: @counterparty, counterparty: @payer, date: Date.new(2025, 3, 3), cents: 30_00)

    seen = [ @payer, @counterparty ].map do |viewer|
      balance = report(viewer).balances.sole
      [ balance.debtor, balance.creditor, balance.money.cents ]
    end

    assert_equal [ [ @counterparty, @payer, 70_00 ] ] * 2, seen
  end

  test "a payment shared with the counterparty as well is still counted once" do
    payment = transfer!(payer: @payer, counterparty: @counterparty, date: Date.new(2025, 3, 2), cents: 100_00)
    EventShare.create!(event: payment.event, profile: @counterparty)
    EventShare.create!(event: payment.event, profile: profiles(:carol))

    assert_equal([ 100_00 ] * 3, [ @payer, @counterparty, profiles(:carol) ].map { |viewer| report(viewer).balances.sole.money.cents })
  end

  test "a repayment reduces what's owed" do
    transfer!(payer: @payer, counterparty: @counterparty, date: Date.new(2025, 3, 2), cents: 100_00)
    repayment = series!("Transaction", profile: @payer, starts_on: Date.new(2025, 3, 10), title: "Paid back", kind: :income,
                                       category: :refund, amount: "40", payment_method: :bank_transfer, counterparty_profile: @counterparty)
    day!(repayment, date: Date.new(2025, 3, 10), status: :completed)

    assert_equal([ 60_00, 60_00 ], [ @payer, @counterparty ].map { |viewer| report(viewer).balances.sole.money.cents })
  end

  test "only completed payments in the period count, at the day's own amount" do
    monthly = series!("Transaction", profile: @payer, starts_on: Date.new(2025, 2, 2), rrule: "FREQ=MONTHLY", title: "Rent share",
                                     kind: :expense, category: :housing, amount: "100", counterparty_profile: @counterparty)
    day!(monthly, date: Date.new(2025, 2, 2), status: :completed)
    day!(monthly, date: Date.new(2025, 3, 2), status: :completed).write_details!(amount_cents: 80_00)
    transfer!(payer: @payer, counterparty: @counterparty, date: Date.new(2025, 3, 5), cents: 999_00, status: :pending)

    assert_equal 80_00, report(@counterparty).balances.sole.money.cents
  end

  test "currencies are never summed together" do
    transfer!(payer: @payer, counterparty: @counterparty, date: Date.new(2025, 3, 2), cents: 100_00, currency: "EUR")
    transfer!(payer: @payer, counterparty: @counterparty, date: Date.new(2025, 3, 3), cents: 50_00, currency: "USD")

    balances = report(@payer).balances

    assert_equal([ [ "EUR", 100_00 ], [ "USD", 50_00 ] ], balances.map { |b| [ b.money.currency, b.money.cents ] })
  end

  test "someone who is neither side nor shares it sees nothing" do
    transfer!(payer: @payer, counterparty: @counterparty, date: Date.new(2025, 3, 2), cents: 100_00)

    assert_not report(profiles(:carol)).any?
  end

  test "nothing to settle renders as empty, not a zero balance" do
    assert_not report(@payer).any?
    assert_empty report(@payer).balances
  end

  private

  def report(viewer)
    Reports::Finance::Settlements.new(audience: audience_for(viewer), period: @march)
  end
end
