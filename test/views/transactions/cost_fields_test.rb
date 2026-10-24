# frozen_string_literal: true

require "test_helper"

# The cost section inside another record's form: a fee's or a bill's asks
# the amount and the method, a purchase's who was paid too.
class Views::Transactions::CostFieldsTest < ActiveSupport::TestCase
  test "a cost not logged yet asks the amount and the method, nothing required, its method not said" do
    fields = parse(Views::Transactions::CostFields.new(cost: nil, currency: "EUR"))

    assert_equal(%w[transaction[amount] transaction[payment_method]], fields.css("[name]").map { _1["name"] })
    assert_empty fields.css("[required]")
    assert_equal "transaction-form", fields.at_css(".cost-fields")["data-controller"]
    assert_equal([ "", "card", "cash", "bank_transfer" ], fields.css("#transaction_payment_method option").map { _1["value"] })
    assert_equal "", fields.at_css("#transaction_payment_method option[selected]")["value"]
    assert_equal "paymentMethod", fields.at_css("#transaction_payment_method")["data-transaction-form-target"]
  end

  test "a purchase's asks who was paid, typed or picked among the housemates, showing the field in use" do
    alice, bob = profiles(:alice), profiles(:bob)
    paid_to_bob = Transaction::Details.new(amount: "12.50", payment_method: "cash", counterparty_profile: bob)

    fields = parse(Views::Transactions::CostFields.new(cost: paid_to_bob, currency: "EUR", counterparties: [ bob ]))

    assert_equal(%w[transaction[amount] transaction[counterparty_mode] transaction[counterparty] transaction[counterparty_profile_id] transaction[payment_method]],
                 fields.css("[name]").map { _1["name"] })
    assert_equal "12.5", fields.at_css("#transaction_amount")["value"]
    assert_equal "cash", fields.at_css("#transaction_payment_method option[selected]")["value"]
    assert_equal "profile", fields.at_css("#transaction_counterparty_mode option[selected]")["value"]
    assert fields.at_css("#transaction_counterparty").has_attribute?("disabled"), "the typed name is out of use"
    assert_equal bob.id.to_s, fields.at_css("#transaction_counterparty_profile_id option[selected]")["value"]
    assert_nil fields.at_css("#transaction_counterparty_profile_id option[value='#{alice.id}']"), "only the housemates given"
  end

  test "the amount steps by the smallest amount its currency has: a cost logged keeps its own" do
    yen = parse(Views::Transactions::CostFields.new(cost: nil, currency: "JPY")).at_css("#transaction_amount")
    euro = parse(Views::Transactions::CostFields.new(cost: Transaction::Details.new(amount: "4.50", currency: "EUR"), currency: "JPY"))
      .at_css("#transaction_amount")

    assert_equal %w[1 1], [ yen["step"], yen["min"] ]
    assert_equal %w[0.01 0.01], [ euro["step"], euro["min"] ]
  end

  private

  def parse(view) = Nokogiri::HTML5.fragment(ApplicationController.render(view, layout: false))
end
