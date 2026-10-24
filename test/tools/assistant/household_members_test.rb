# frozen_string_literal: true

require "test_helper"

# Sharing with, and payments with, other household members.
class Assistant::HouseholdMembersTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12)
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
    @marco = AssistantEval::Seeds.household_member(@profile)
  end

  teardown { travel_back }

  def apply(result) = Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(result[:data][:change_set_id]), confirmed: true)
  def payment = days_of(Transaction, @profile).sole
  def read_by(person, day) = Assistant::Resources.fetch("transaction").summarize(day, profile: person)

  test "sharing waits for the button, then Marco can see it and hears about it; Undo stops sharing" do
    appointment = AssistantEval::Seeds.moretti_oct2(@profile)

    result = run_tool(:share, @chat, type: "appointment", ref: "Moretti", with: "Marco")
    assert_equal "waiting_for_user", result[:data][:status], result.inspect
    assert_empty appointment.event.event_shares

    apply(result)
    assert_equal [ @marco.id ], appointment.event.event_shares.reload.map(&:profile_id)
    assert Event.accessible_by(@marco).exists?(appointment.event.id)
    assert_equal [ [ appointment.event, @profile ] ], @marco.notifications.shared.map { [ _1.subject, _1.actor ] }, "told, as from the share modal"

    Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))
    assert_empty appointment.event.event_shares.reload
  end

  test "only the owner shares; stopping to share applies right away" do
    therapy = Collection.find_by!(profile: @profile, name: "B12")
    CollectionShare.create!(collection: therapy, profile: @marco)

    marco_chat = assistant_chat(@marco)
    refused = run_tool(:share, marco_chat, type: "collection", ref: "B12", with: "Try")
    assert_match "not the user's", refused.to_s

    result = run_tool(:share, @chat, type: "therapy", ref: "B12", with: "Marco", undo: true)
    assert_equal "saved", result[:data][:status], result.inspect
    assert_empty therapy.collection_shares.reload
  end

  test "share takes a series' event_id instead of ref" do
    appointment = AssistantEval::Seeds.moretti_oct2(@profile)
    travel_to appointment.date.in_time_zone.change(hour: 12) # event_id alone means today's occurrence

    result = run_tool(:share, @chat, type: "appointment", event_id: appointment.event.id, with: "Marco")

    assert_equal "waiting_for_user", result[:data][:status], result.inspect
  end

  test "someone who isn't in the household is named back, with who is" do
    AssistantEval::Seeds.moretti_oct2(@profile)

    result = run_tool(:share, @chat, type: "appointment", ref: "Moretti", with: "Giulia")

    assert_match(/nobody called Giulia in the household \(there is: .*Marco/, result.to_s)
  end

  test "money from a household member waits for the button, since they will see it; then it is linked to them, and they see their side" do
    result = run_tool(:record_payment, @chat, title: "Rent share", amount: 50, kind: "income", category: "housing",
                                              payment_method: "bank_transfer", member: "Marco", date: "today")

    assert_equal "waiting_for_user", result[:data][:status], result.inspect
    assert_equal [ "Marco" ], result[:data][:changes].sole[:seen_by]
    assert_match "Marco will see this", result[:data][:next]
    assert_empty days_of(Transaction, @profile)
    apply(result)
    assert_equal [ @marco.id, "income", 50 ], [ payment.event.details.counterparty_profile_id, payment.details.kind, amount_of(payment).to_i ]
    assert_empty Event.where(profile: @marco), "one payment, two readers: no copy on Marco's side"
    assert_equal [ "expense", "Try" ], read_by(@marco, payment).values_at(:kind, :paid_to)
    assert_equal [ "income", "Marco" ], read_by(@profile, payment).values_at(:kind, :paid_to)
  end

  test "a household member's name given as counterparty (not member) still links them" do
    result = run_tool(:record_payment, @chat, title: "Rent share", amount: 50, kind: "income", category: "housing",
                                              payment_method: "bank_transfer", counterparty: "Marco", date: "today")

    assert_equal "waiting_for_user", result[:data][:status], result.inspect
    apply(result)
    assert_equal @marco.id, payment.event.details.counterparty_profile_id
    assert_nil payment.details.counterparty, "free text is dropped once it resolves to a member"
    assert Event.accessible_by(@marco).exists?(payment.event_id), "Marco reads it from his side"
  end

  test "a shop or doctor's name, unlike a member's, stays free text" do
    result = run_tool(:record_payment, @chat, title: "Vet visit", amount: 40, kind: "expense", category: "healthcare",
                                              payment_method: "cash", counterparty: "the vet clinic", date: "today")

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal "the vet clinic", payment.details.counterparty
    assert_nil payment.event.details.counterparty_profile_id
  end

  test "update_record links a member given as counterparty text too" do
    result = run_tool(:record_payment, @chat, title: "Rent share", amount: 50, kind: "income", category: "housing",
                                              payment_method: "bank_transfer", counterparty: "someone else", date: "today")
    assert_equal "saved", result[:data][:status], result.inspect

    updated = run_tool(:update_record, @chat, type: "transaction", ref: payment.id.to_s, changes: { counterparty: "Marco" })

    assert_equal "waiting_for_user", updated[:data][:status], "the change lets Marco in: #{updated.inspect}"
    assert_equal [ "Marco" ], updated[:data][:changes].sole[:seen_by]
    apply(updated)
    assert_equal @marco.id, payment.event.details.counterparty_profile_id
    assert_nil payment.details.counterparty
  end

  test "a payment's date is kept (it used to be dropped as not understood)" do
    result = run_tool(:record_payment, @chat, title: "Electricity", amount: 80, kind: "expense", category: "utilities",
                                              payment_method: "card", date: "2026-09-20")

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal Date.new(2026, 9, 20), payment.date
    assert_predicate payment, :completed?, "a past payment is saved as paid"
  end

  test "the model is told who is in the household" do
    assert_includes Assistant::Context.new(@chat).to_prompt, "Household members:"
    assert_includes Assistant::Context.new(@chat).to_prompt, "Marco"
  end
end
