# frozen_string_literal: true

require "test_helper"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
    sign_in @alice
    @day = Date.new(2026, 10, 6)
  end

  test "a payment to a housemate: one series, the housemate reads it without changing it" do
    post transactions_path, as: :turbo_stream, params: {
      transaction: { title: "Shared groceries", date: @day.iso8601,
                     details_attributes: { amount: "30", kind: "expense", category: "groceries", payment_method: "card",
                                           counterparty_mode: "profile", counterparty_profile_id: @bob.id } },
      event: { frequency: "none" }
    }

    assert_response :success
    payment = Transaction.find_by!(title: "Shared groceries")
    assert_equal [ @bob.id, 3000 ], [ payment.details.counterparty_profile_id, payment.details.amount_cents ]
    day = payment.first_occurrence.tap(&:materialize!)

    sign_in @bob
    get edit_event_day_path(day.event, day.date), as: :turbo_stream
    assert_response :success
    assert_select "fieldset.modal__readonly[disabled]"
    assert_select "input[type=submit]", 0
    assert_select ".modal__footer .modal__btn--cancel", text: I18n.t("modal.close"), message: "nothing to cancel on a form only read"

    patch event_day_path(day.event, day.date), as: :turbo_stream, params: { transaction: { title: "Mine now" }, event: { frequency: "none" } }
    assert_equal "Shared groceries", payment.reload.title
  end

  test "the form asks for no currency: a new payment is in the household's, a saved one keeps its own" do
    @alice.household.update!(currency: "CHF")

    get new_transaction_path, as: :turbo_stream
    assert_select "input[name='transaction[details_attributes][amount]']"
    assert_select "[name='transaction[details_attributes][currency]']", 0

    post transactions_path, as: :turbo_stream, params: {
      transaction: { title: "Train", date: @day.iso8601,
                     details_attributes: { amount: "12", currency: "USD", kind: "expense", category: "transportation", payment_method: "card" } },
      event: { frequency: "none" }
    }
    train = Transaction.find_by!(title: "Train")
    assert_equal "CHF", train.details.currency

    train.details.update!(currency: "EUR")
    patch event_day_path(train, train.starts_on), as: :turbo_stream, params: {
      transaction: { title: "Train home", details_attributes: { amount: "14", kind: "expense", category: "transportation", payment_method: "card" } },
      event: { frequency: "none" }
    }
    assert_equal [ "Train home", "EUR" ], [ train.reload.title, train.details.reload.currency ]
  end

  test "a day's status says received for money coming in and paid for money going out" do
    { "income" => "received", "expense" => "completed" }.each do |kind, word|
      day = day!(series!("Transaction", profile: @alice, starts_on: @day, title: kind, kind: kind), date: @day)

      get edit_event_day_path(day.event, day.date), as: :turbo_stream

      assert_select "select[name='transaction[status]'] option[value=completed]", text: I18n.t("transactions.status.#{word}")
    end
  end

  test "a day's done status carries both words, for the form to change with the kind" do
    day = day!(series!("Transaction", profile: @alice, starts_on: @day, title: "Rent", kind: :expense), date: @day)

    get edit_event_day_path(day.event, day.date), as: :turbo_stream

    assert_select "select[name='transaction[details_attributes][kind]'][data-transaction-form-target=kind]"
    assert_select "option[value=completed][data-transaction-form-target=doneOption]" \
                  "[data-paid-label=?][data-received-label=?]", I18n.t("transactions.status.completed"), I18n.t("transactions.status.received")
  end

  test "on a day of a recurring payment the housemate is the series': sent only for the whole series" do
    day = transfer!(payer: @alice, counterparty: @bob, date: @day, cents: 1500)
    day.event.update!(rrule: "FREQ=MONTHLY")

    get edit_event_day_path(day.event, day.date), as: :turbo_stream

    assert_select "select[name='transaction[details_attributes][counterparty_profile_id]'][disabled][data-apply-to-scope=series][data-apply-to-held]" do
      assert_select "option[selected][value=?]", @bob.id.to_s
    end

    patch event_day_path(day.event, day.date), as: :turbo_stream, params: {
      transaction: { title: day.title, apply_to: "day",
                     details_attributes: { amount: "20", kind: "expense", category: "groceries", payment_method: "card", counterparty_mode: "profile" } },
      event: { frequency: "monthly", interval: 1 }
    }

    assert_response :success
    assert_equal 2000, day.reload.details.amount_cents
    assert_equal 1500, day.event.details.reload.amount_cents, "the other months keep their amount"
    assert_equal @bob.id, day.event.details.counterparty_profile_id
  end

  test "a cost for something the viewer can't reach isn't about it" do
    stranger = series!("LabTestResult", profile: profiles(:carol), starts_on: @day, title: "Not yours").first_occurrence.materialize!

    get new_transaction_path(about_type: "Occurrence", about_id: stranger.id), as: :turbo_stream

    assert_response :success
    assert_select "input[name='transaction[details_attributes][about_id]']", 0
  end
end
