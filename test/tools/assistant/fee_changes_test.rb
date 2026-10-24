# frozen_string_literal: true

require "test_helper"

# A visit's or purchase's price is changed on the visit or purchase — the
# attached payment follows (Operations::Update::Price), keeping who it
# was paid to, and Undo puts it back.
class Assistant::FeeChangesTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12)
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
  end

  teardown { travel_back }

  def appointments = days_of(Appointment, @profile)

  test "correcting a paid visit's price keeps it paid, and Undo restores the old price" do
    AssistantEval::Seeds.dentist_sep22_paid_60(@profile)

    result = run_tool(:update_record, @chat, type: "appointment", ref: "dentist Tuesday", changes: { amount: 80 })

    assert_equal "saved", result[:data][:status], result.inspect
    fee = appointments.sole.costs.sole
    assert_equal [ 80, "completed", "Dentist" ], [ amount_of(fee).to_i, fee.status, fee.details.counterparty ]

    Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))
    assert_equal 60, amount_of(fee.reload).to_i
  end

  test "a new payment the same day and payee, for a different amount, points at the existing fee instead" do
    AssistantEval::Seeds.dentist_sep22_paid_60(@profile)
    fee = appointments.sole.costs.sole

    result = run_tool(:record_payment, @chat, title: "Dentist", amount: 80, kind: "expense", category: "healthcare",
                                              payment_method: "card", counterparty: "Dentist", date: "2026-09-22")

    assert_equal "waiting_for_user", result[:data][:status], result.inspect
    hint = result[:data][:changes].sole[:warnings].sole["hint"]
    assert_match(/same day, with the same payee \(id #{fee.id}\).*60\.0 EUR.*update_record with ref #{fee.id}/, hint)
    assert_equal 60, amount_of(fee.reload).to_i, "nothing saved until confirmed"
  end

  test "a price for a visit that had none adds an unpaid fee; Undo removes it" do
    AssistantEval::Seeds.moretti_oct2(@profile)

    result = run_tool(:update_record, @chat, type: "appointment", ref: "Moretti", changes: { amount: 50, payment_method: "cash" })

    assert_equal "saved", result[:data][:status], result.inspect
    fee = appointments.sole.costs.sole
    assert_equal [ 50, "pending", "cash" ], [ amount_of(fee).to_i, fee.status, paid_with(fee) ]

    Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))
    assert_empty appointments.sole.costs
    assert_not Event.exists?(fee.event_id), "the fee's series goes with it"
  end

  test "a payment method alone for a visit with no price asks for the price" do
    AssistantEval::Seeds.moretti_oct2(@profile)

    result = run_tool(:update_record, @chat, type: "appointment", ref: "Moretti", changes: { payment_method: "cash" })

    assert_match "give amount too", result.to_s
    assert_empty appointments.sole.costs
  end

  test "the same payment sent again the same day is refused; a day later it may be a second one" do
    AssistantEval::Seeds.dentist_sep22_paid_60(@profile)
    payment = { title: "Dentist", amount: 60, kind: "expense", category: "healthcare", payment_method: "card", counterparty: "Dentist" }

    again = run_tool(:record_payment, @chat, **payment, date: "2026-09-22")
    assert_equal false, again[:ok], again.inspect
    assert_match "already exists on 2026-09-22", again[:error]

    later = run_tool(:record_payment, assistant_chat(@profile), **payment, date: "2026-09-23")
    assert_equal "waiting_for_user", later[:data][:status], later.inspect
    assert_nil later[:data][:changes].sole[:warnings].sole["hint"], "the same amount is no correction"
  end
end
