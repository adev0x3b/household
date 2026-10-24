# frozen_string_literal: true

require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  def money(**details)
    Transaction.new(profile: profiles(:alice), starts_on: Date.current, title: "Rent",
                    details_attributes: { amount: "10", currency: "EUR", kind: :expense, category: :housing, payment_method: :card }.merge(details))
  end

  test "requires a title" do
    transaction = money(amount: "12.50")
    transaction.title = nil
    assert_not transaction.valid?
    assert_includes transaction.errors[:title], "can't be blank"
  end

  test "requires a valid currency, normalized to uppercase" do
    assert_not money(currency: "EU").valid?

    transaction = money(currency: "eur")
    transaction.valid?
    assert_equal "EUR", transaction.details.currency
  end

  test "an amount is how much, more than zero: the kind says which way" do
    %w[0 -10].each do |typed|
      transaction = money(amount: typed)
      assert_not transaction.valid?, typed
      assert_includes transaction.errors["details.amount"], "must be more than zero", typed
    end

    expense = money(amount: "10")
    income = money(amount: "10", kind: :income, category: :salary)
    assert_equal [ true, true ], [ expense.valid?, income.valid? ]
    assert_equal [ 1000, 1000 ], [ expense.details.amount_cents, income.details.amount_cents ]
  end

  test "an amount has no more decimals than its currency: a yen has no cents" do
    yen = money(amount: "1200.50", currency: "JPY")
    assert_not yen.valid?
    assert_includes yen.errors["details.amount"], "has more decimals than JPY has"

    assert_predicate money(amount: "1200", currency: "JPY"), :valid?
    assert_predicate money(amount: "12.34", currency: "EUR"), :valid?
  end

  test "converts amount input into cents" do
    details = Transaction::Details.new
    details.amount = "12.34"

    assert_equal 1234, details.amount_cents
    assert_equal BigDecimal("12.34"), details.amount
  end

  test "a day's money is its own when overridden, else the series'" do
    day = occurrences(:electricity_due)
    assert_equal 12500, day.details.amount_cents
    assert_equal "Utility Company", day.details.counterparty

    day.write_details!(amount: "99")
    assert_equal 9900, day.details.amount_cents
    assert_equal "expense", day.details.kind, "inherited"
    assert_equal 12500, occurrences(:electricity_paid).details.amount_cents
  end

  # A day's row keeps only what differs from the series, so a sign stored
  # with its amount would keep the kind the series had when the day was
  # changed.
  test "a day's own amount reads the way the series goes after the series changes kind" do
    alice = profiles(:alice)
    event = series!("Transaction", profile: alice, starts_on: Date.current, title: "Rent", rrule: "FREQ=MONTHLY",
                                   kind: :expense, amount: "10")
    event.occurrence_on(Date.current.next_month).write_details!(amount: "20")

    event.details.assign_attributes(kind: :income, amount: "10")
    event.save!

    month = event.reload.occurrence_on(Date.current.next_month)
    assert_equal [ "income", 2000 ], [ month.details.kind, event.signed_cents_for(alice, month.details) ]
    assert_equal 2000, Occurrence.with_series(Transaction).where(id: month.id).pick(Arel.sql(Transaction.viewer_amount_sql(alice)))
  end

  test "a day of another kind than its series is signed by its own" do
    day = occurrences(:electricity_due)
    day.write_details!(kind: :income, category: :refund)

    assert_equal "income", events(:electricity_bill).kind_for(profiles(:alice), day.details)
    assert_equal 12500, events(:electricity_bill).signed_cents_for(profiles(:alice), day.details)
    assert_equal(-12500, events(:electricity_bill).signed_cents_for(profiles(:alice)), "the series is still an expense")
  end

  test "what it is about: the series' row names a series or a purchase, a day's row names a day" do
    series = events(:electricity_bill).details
    assert_equal events(:groceries), series.about
    assert_equal occurrences(:groceries_due), occurrences(:electricity_due).own_details.about
    assert_equal occurrences(:groceries_due), events(:electricity_bill).about_for(occurrences(:electricity_due))
    projected = events(:electricity_bill).about_for(events(:electricity_bill).occurrence_on(Date.new(2026, 3, 16)))
    assert_equal [ events(:groceries).id, Date.new(2026, 3, 16), true ], [ projected.event_id, projected.date, projected.projected? ], "the series' same day"
    assert_equal occurrences(:groceries_due), events(:electricity_bill).about_day(occurrences(:electricity_due))
    assert_nil events(:groceries).about_day(occurrences(:groceries_due)), "a task is about nothing but itself"

    series.about = occurrences(:groceries_due)
    assert_not series.valid?, "a series' row isn't about a day"
    series.about = events(:electricity_bill)
    assert_not series.valid?, "a transaction takes no costs"
    series.about = profiles(:alice)
    assert_not series.valid?

    day = occurrences(:electricity_due).own_details
    day.about = events(:groceries)
    assert_not day.valid?, "a day's row isn't about a series"
    day.about = occurrences(:electricity_paid)
    assert_includes day.tap(&:valid?).errors[:about], "doesn't take costs", "a payment's day takes no costs"
  end

  test "a cost can't be about someone else's day" do
    carols = appointment!(profile: profiles(:carol), date: Date.current)

    error = assert_raises(ActiveRecord::RecordInvalid) { expense!(profile: profiles(:alice), date: Date.current, cents: 100, about: carols) }
    assert_match "isn't one you have access to", error.message
    assert_predicate expense!(profile: profiles(:carol), date: Date.current, cents: 100, about: carols), :persisted?
  end

  test "the counterparty is a housemate, never yourself, and only on the series" do
    transaction = money(counterparty_profile: profiles(:alice))
    assert_not transaction.valid?
    assert_predicate transaction.errors["details.counterparty_profile"], :any?

    assert_not money(counterparty_profile: profiles(:outsider)).valid?

    transaction = money(counterparty_profile: profiles(:bob), counterparty: "Bob")
    assert_not transaction.valid?, "a name and a member at once"

    day = occurrences(:electricity_due)
    override = day.override_details
    override.counterparty_profile = profiles(:bob)
    assert_not override.valid?
  end

  test "counterparty display name uses the linked profile's label" do
    details = Transaction::Details.new(counterparty_profile: profiles(:bob))
    assert_equal "Bob", details.counterparty_display_name
    assert_equal "Utility Company", events(:electricity_bill).details.counterparty_display_name
  end

  test "a payment between housemates is one series read from both sides" do
    paid = transfer!(payer: profiles(:alice), counterparty: profiles(:bob), date: Date.new(2026, 3, 2), cents: 3800)
    event = paid.event

    assert_equal "expense", event.kind_for(profiles(:alice))
    assert_equal "income", event.kind_for(profiles(:bob))
    assert_equal 3800, paid.details.amount_cents
    assert_equal(-3800, event.signed_cents_for(profiles(:alice), paid.details))
    assert_equal 3800, event.signed_cents_for(profiles(:bob), paid.details)
    assert_equal "expense", event.kind_for(profiles(:carol))

    viewer_cents = Occurrence.of_type(Transaction).with_series(Transaction).where(id: paid.id)
      .pluck(Arel.sql(Transaction.viewer_amount_sql(profiles(:bob)))).first
    assert_equal 3800, viewer_cents
    assert_equal 0, Occurrence.with_series(Transaction).where(id: paid.id).pluck(Arel.sql(Transaction.viewer_kind_sql(profiles(:bob)))).first
  end

  test "a day exposes the costs about it" do
    assert_equal [ occurrences(:electricity_due) ], occurrences(:groceries_due).costs.to_a
    assert_equal occurrences(:electricity_paid), occurrences(:groceries_done).cost
    assert_empty occurrences(:electricity_due).costs, "a transaction's day takes no costs"
  end
end
