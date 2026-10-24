# frozen_string_literal: true

require "test_helper"

class Reports::Finance::AttentionItemsTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2025, 3, 15)
  end

  test "a bill never logged needs attention however long ago, opening its day; a logged or cancelled one doesn't" do
    bill = series!("Transaction", profile: @profile, starts_on: Date.new(2025, 2, 10), rrule: "FREQ=MONTHLY", title: "Electricity",
                                  kind: :expense, category: :utilities, amount: "60")
    day!(bill, date: Date.new(2025, 2, 10), status: :completed)
    expense!(profile: @profile, date: @today - 3, cents: 500)
    expense!(profile: @profile, date: @today - 20, cents: 500, status: :pending, title: "Plumber")
    expense!(profile: @profile, date: Date.new(2024, 6, 1), cents: 500, status: :pending, title: "Last year's")
    expense!(profile: @profile, date: @today - 5, cents: 500, status: :cancelled, title: "Called off")

    items = attention(@profile)

    assert_equal [ [ "Electricity", Date.new(2025, 3, 10), true ], [ "Last year's", Date.new(2024, 6, 1), false ], [ "Plumber", @today - 20, false ] ],
                 items.map { |item| [ item.subject, item.date, item.occurrence.projected? ] }.sort
  end

  test "a payment a housemate logged against the viewer is theirs to log, not the viewer's" do
    transfer!(payer: profiles(:bob), counterparty: @profile, date: @today - 2, cents: 500, status: :pending)

    assert_empty attention(@profile).to_a
    assert_equal [ :overdue_transaction ], attention(profiles(:bob)).map(&:kind)
  end

  private

  def attention(viewer)
    Reports::Finance::AttentionItems.new(audience: audience_for(viewer), today: @today)
  end
end
