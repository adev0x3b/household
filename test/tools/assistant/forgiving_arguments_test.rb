# frozen_string_literal: true

require "test_helper"

# The shapes models actually send, read from failed calls in saved eval runs:
# a series' event_id as ref, "event_id 42 date …" as ref, a date next to ref,
# a visit's "cost" or "price".
class Assistant::ForgivingArgumentsTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12) # a Thursday: a dose is due
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
    # Fresh test tables number series and days alike; a bare id is only
    # read as a series when no day has it.
    ActiveRecord::Base.connection.execute("SELECT setval('events_id_seq', nextval('events_id_seq') + 1000)")
    AssistantEval::Seeds.b12_injection_series(@profile)
    @series = Medication.where(profile: @profile).sole
  end

  teardown { travel_back }

  def dose_on(day) = @series.occurrence_on(day)
  def apply(result) = Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(result[:data][:change_set_id]), confirmed: true)
  def payment_with(person) = days_of(Transaction, @profile).joins(:event).merge(Event.where(id: Transaction::Details.series.where(counterparty_profile: person).select(:event_id)))

  test "a series' event_id as ref means today's dose" do
    result = run_tool(:mark_done, @chat, type: "medication", ref: @series.id.to_s)

    assert_equal "saved", result[:data][:status], result.inspect
    assert_predicate dose_on(Date.new(2026, 9, 24)), :completed?
  end

  test "event_id as its own keyword (not folded into ref) works the same as ref" do
    result = run_tool(:mark_done, @chat, type: "medication", event_id: @series.id)

    assert_equal "saved", result[:data][:status], result.inspect
    assert_predicate dose_on(Date.new(2026, 9, 24)), :completed?
  end

  test "an event_id with a day, written into ref or passed as date" do
    run_tool(:mark_done, @chat, type: "medication", ref: "event_id #{@series.id} date 2026-09-17")
    run_tool(:mark_done, @chat, type: "medication", ref: @series.id.to_s, date: "2026-09-10", status: "skipped")

    assert_predicate dose_on(Date.new(2026, 9, 17)), :completed?
    assert_predicate dose_on(Date.new(2026, 9, 10)), :skipped?
  end

  test "a day the series has nothing on, or a series not due today, says what to send" do
    off_day = run_tool(:mark_done, @chat, type: "medication", ref: "event_id #{@series.id} on 2026-09-16")
    assert_match(/has nothing on 2026-09-16/, off_day.inspect)

    travel_to Time.zone.local(2026, 9, 25, 12)
    not_today = run_tool(:mark_done, @chat, type: "medication", ref: @series.id.to_s)
    assert_match(/isn't due today — say which day/, not_today.inspect)
    named = run_tool(:mark_done, @chat, type: "medication", ref: "event_id #{@series.id}")
    assert_match(/has nothing on 2026-09-25 — say which day/, named.inspect)
  end

  test "mark_done takes a date with the user's words, and with all for one day" do
    run_tool(:mark_done, @chat, type: "medication", ref: "cobalamin", date: "a week ago")
    assert_predicate dose_on(Date.new(2026, 9, 17)), :completed?

    run_tool(:mark_done, @chat, type: "medication", all: true, date: "2026-09-10")
    assert_predicate dose_on(Date.new(2026, 9, 10)), :completed?
    assert_not dose_on(Date.new(2026, 9, 3)).completed?, "only that day"
  end

  test "a visit's cost or price is its fee" do
    AssistantEval::Seeds.moretti_oct2_with_fee(@profile)
    appointment = days_of(Appointment, @profile).sole

    result = run_tool(:update_record, @chat, type: "appointment", ref: "Moretti", changes: { cost: 70, cost_status: "pending" })

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal 70, amount_of(appointment.costs.sole).to_i
  end

  test "an unknown field lists the fee fields too" do
    AssistantEval::Seeds.moretti_oct2(@profile)

    result = run_tool(:update_record, @chat, type: "appointment", ref: "Moretti", changes: { color: "blue" })

    assert_match(/unknown fields color; allowed: .*amount \(its fee\)/, result.inspect)
  end

  test "a payment's title comes from what was said, and \"rent\" is housing — only the payment method is asked" do
    marco = AssistantEval::Seeds.household_member(@profile)

    asked = run_tool(:record_payment, @chat, amount: 50, kind: "income", category: "rent", member: "Marco", date: "today")
    assert_equal [ "transaction.payment_method" ], asked[:data][:changes].sole[:missing], asked.inspect

    held = run_tool(:record_payment, @chat, amount: 50, kind: "income", category: "rent", member: "Marco", date: "today",
                                            payment_method: "bank transfer")
    assert_equal "waiting_for_user", held[:data][:status], held.inspect
    apply(held)
    payment = payment_with(marco).sole
    assert_equal [ "housing", "Housing with Marco" ], [ payment.details.category, payment.title ]
  end

  test "creating a dose of a repeating medication points at the series instead" do
    result = run_tool(:record_medication, @chat, name: "Cobalamin injection", kind: "injection", area: "thigh", side: "left",
                                                 date: "today", taken: true)

    hint = result[:data][:changes].sole[:warnings].sole["hint"]
    assert_match(/already repeats \(event_id #{@series.id}\).*mark_done or update_record/, hint)
  end

  test "a duplicate's hint leads next even while other fields are still missing" do
    result = run_tool(:record_medication, @chat, name: "Cobalamin injection", kind: "injection", date: "today", taken: true)

    assert_equal "needs_input", result[:data][:status], result.inspect
    assert_equal %w[medication.area medication.side], result[:data][:changes].sole[:missing]
    assert_match(/\ANOT SAVED YET\. This already repeats \(event_id #{@series.id}\)/, result[:data][:next])
    assert_no_match(/what is listed as missing/, result[:data][:next])
  end

  test "a price given once for a single grocery item is that item's price" do
    result = run_tool(:record_groceries, @chat, items: [ { ingredient: "linguine", quantity: 500, unit: "g" } ], amount: 0.99, payment_method: "cash")

    assert_equal "saved", result[:data][:status], result.inspect
    purchase = IngredientPurchase.where(profile: @profile).sole
    assert_in_delta(0.99, amount_of(purchase.costs.sole).to_f)
  end

  test "a price given once for several items is asked per item, never split by guess" do
    result = run_tool(:record_groceries, @chat, items: [ { ingredient: "flour" }, { ingredient: "eggs" } ], amount: 7, payment_method: "cash")

    assert_equal "needs_input", result[:data][:status], result.inspect
    assert_equal 2, result[:data][:changes].size
    assert result[:data][:changes].all? { |change| change[:missing].join(" ").include?("transaction.amount") }, result.inspect
    assert_empty IngredientPurchase.where(profile: @profile)
  end

  test "a single supply with its price at the top level is saved the same way" do
    result = run_tool(:record_purchases, @chat, therapy: "B12", payment_method: "card", items: [ { supply: "Swabs", quantity: 200 } ], total: 12)

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal 12, amount_of(SupplyPurchase.where(profile: @profile).joins(:supply).find_by(supplies: { name: "Swabs" }).costs.sole).to_i
  end

  test "money with a household member asks which way it went instead of assuming an expense" do
    marco = AssistantEval::Seeds.household_member(@profile)

    asked = run_tool(:record_payment, @chat, amount: 50, category: "rent", member: "Marco", date: "today", payment_method: "bank transfer")
    assert_equal "needs_input", asked[:data][:status], asked.inspect
    assert_match(/transaction\.kind/, asked[:data][:changes].sole[:missing].join(" "))
    assert_empty payment_with(marco)

    held = run_tool(:record_payment, @chat, kind: "income")
    assert_equal "waiting_for_user", held[:data][:status], held.inspect
    apply(held)
    assert_equal "income", payment_with(marco).sole.details.kind
  end

  test "steps and grocery items sent as bare words are read as their instruction and name" do
    recipe = run_tool(:add_recipe, @chat, name: "Toast", steps: [ "Toast the bread", "Butter it" ], ingredients: [ { ingredient: "Bread", quantity: 2 } ])
    assert_equal "saved", recipe[:data][:status], recipe.inspect
    assert_equal [ "Toast the bread", "Butter it" ], Recipe.find_by!(profile: @profile, name: "Toast").recipe_steps.map(&:instruction)

    list = run_tool(:add_grocery_list, @chat, name: "Weekend", items: [ "Milk", "Eggs" ])
    assert_equal "saved", list[:data][:status], list.inspect
    assert_equal %w[Eggs Milk], GroceryList.find_by!(profile: @profile, name: "Weekend").grocery_list_items.map { _1.ingredient.name }.sort
  end
end
