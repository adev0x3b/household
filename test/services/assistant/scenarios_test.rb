# frozen_string_literal: true

require "test_helper"

# The brief's scenarios and the reports that shaped the design, replayed as
# the change-set operations the write tools submit (with what the user said in
# between). Asserts what ends up in the database — no model involved.
class Assistant::ScenariosTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @b12 = collections(:b12)
    travel_to Time.zone.local(2026, 9, 22, 10)
  end

  teardown { travel_back }

  def propose(chat, _intents, operations, **options)
    submit_changes(chat, operations, **options)
  end

  test "scenario 1: bought the vial, needles and syringes for B12" do
    needles = supply_purchase!(profile: @alice, name: "Needles", collection: @b12).supply
    chat = assistant_chat(@alice)
    item = ->(supply, **fields) { { intent: 0, op: "create", type: "supply_purchase", fields: { supply: supply, therapy: "B12", **fields } } }

    # "I bought the vial of vitamins, needles and syringes for my B12 therapy"
    asked = propose(chat, [ "log the B12 purchases" ], [ item.("Cobalamin injection"), item.("Needles"), item.("Syringes") ])
    assert_equal "needs_input", asked[:data][:status]
    assert(asked[:data][:changes].all? { |op| op[:missing].include?("transaction.amount") })

    # "1 vial for 32 euros, 100 needles for 12 and 50 syringes for 8, all by card"
    saved = propose(chat, [ "log the B12 purchases" ], [ item.("Cobalamin injection", quantity: 1, amount: "32 euros", payment_method: "card"),
                                                         item.("Needles", quantity: 100, amount: "12", payment_method: "Card"),
                                                         item.("Syringes", quantity: 50, amount: "8", payment_method: "card") ])
    assert_equal "waiting_for_user", saved[:data][:status], "Bob shares the therapy, so he will see the purchases: #{saved.inspect}"
    Assistant::ChangeSets::Applier.call(Assistant::ChangeSet.find(saved[:data][:change_set_id]), confirmed: true)

    purchases = SupplyPurchase.where(profile: @alice, purchased_on: Date.current).includes(:supply)
    assert_equal({ "Cobalamin injection" => 1, "Needles" => 100, "Syringes" => 50 }, purchases.to_h { |p| [ p.supply.name, p.quantity_purchased.to_i ] })
    assert(purchases.all? { |p| p.collection == @b12 })
    assert_equal needles, purchases.find { |p| p.supply.name == "Needles" }.supply, "the existing supply is reused"
    assert_equal [ 3200, 1200, 800 ].sort, purchases.flat_map(&:costs).map { |cost| cost.details.amount_cents }.sort
  end

  test "scenario 2: Moretti booking stops on a duplicate, then is completed on the day" do
    appointment!(profile: @alice, date: Date.new(2026, 10, 2), counterpart: "Moretti")
    chat = assistant_chat(@alice)
    booking = ->(fields) { [ { intent: 0, op: "create", type: "appointment", fields: { provider: "Moretti", date: "this friday", amount: "50" }.merge(fields) } ] }

    # "I made an appointment with doctor Moretti for this friday. It will cost 50 bucks"
    first = propose(chat, [ "book Moretti" ], booking.({}))
    assert_equal "needs_input", first[:data][:status]
    assert_predicate first[:data][:changes].sole[:warnings], :present?, "the Moretti visit on Oct 2 is pointed out"

    # "Please create a new one" … "Card, and the time is 11:00"
    saved = propose(chat, [ "book Moretti" ], booking.(time: "11:00", payment_method: "card"), confirm: true)
    assert_equal "saved", saved[:data][:status], saved.inspect
    booked = appointments_with("Moretti").find_by!(date: Date.new(2026, 9, 25))
    assert_predicate booked.costs.sole, :pending?

    # That Friday: "Appointment done!"
    travel_to Time.zone.local(2026, 9, 25, 18)
    done = propose(chat, [ "the visit is done" ], [ { intent: 0, op: "complete", type: "appointment", ref: "today's visit with Moretti" } ])
    assert_equal "saved", done[:data][:status], done.inspect
    assert_predicate booked.reload, :completed?
    assert_predicate booked.costs.sole, :completed?
  end

  test "a lab report and the doctor's ranges in one message" do
    travel_to Time.zone.local(2026, 9, 23, 12)
    chat = assistant_chat(@alice)
    ranges = { "Cobalamin" => [ "pg/mL", "150 low 250 high 80 critically low 300 critically high" ], "Vitamin D" => [ "ng/mL", "between 20 and 50" ],
               "Homocysteine" => [ "ng/mL", "below 0.8 is good, 1.4 is critically high" ], "Calcium" => [ "mg/dL", "between 8.5 and 10" ] }
    operations = [ { intent: 0, op: "create", type: "lab_test_result", fields: { values: { "Cobalamin" => "250", "Homocysteine" => "0.8", "Calcium" => "3", "Vitamin D" => "20" } } } ] +
                 ranges.map { |analyte, (unit, text)| { intent: 1, op: "set_range", type: "reference_range", fields: { analyte: analyte, unit: unit, range_text: text } } }

    asked = propose(chat, [ "record the lab report", "save the doctor's ranges" ], operations)
    assert_equal "needs_input", asked[:data][:status], "when was the test done?"

    saved = propose(chat, [ "record the lab report" ], [ { intent: 0, op: "create", type: "lab_test_result", fields: { date: "a week ago" } } ])
    assert_equal "saved", saved[:data][:status], saved.inspect

    lab = days_of(LabTestResult, @alice).order(:id).last
    assert_predicate lab, :completed?
    assert_equal [ "Calcium: 3 mg/dL (low)", "Cobalamin: 250 pg/mL (normal)", "Homocysteine: 0.8 ng/mL (normal)", "Vitamin D: 20 ng/mL (normal)" ],
                 Assistant::Resources.lab_values(lab).sort
  end

  test "a correction to a saved report, found by the user's words" do
    travel_to Time.zone.local(2026, 9, 23, 12)
    chat = assistant_chat(@alice)
    propose(chat, [ "record the report" ], [ { intent: 0, op: "create", type: "lab_test_result",
                                               fields: { date: "a week ago", values: { "Calcium" => "300", "Cobalamin" => "250" } } } ])

    # "Calcium was a typo. I have 3" + "those are mg/dL"
    fixed = propose(chat, [ "fix calcium" ], [ { intent: 0, op: "update", type: "lab_test_result", ref: "the lab report from a week ago",
                                                 fields: { values: [ { analyte: "Calcium", value: "3", unit: "mg/dL" } ] } } ])
    assert_equal "saved", fixed[:data][:status], fixed.inspect
    lab = days_of(LabTestResult, @alice).reorder(:id).last
    assert_equal({ "Calcium" => "3", "Cobalamin" => "250" }, lab.lab_test_result_entries.includes(:analyte).to_h { |e| [ e.analyte.name, e.value ] })
  end

  test "future items stay pending unless the user already did them" do
    chat = assistant_chat(@alice)
    propose(chat, [ "cactus", "vitamins" ], [ { intent: 0, op: "create", type: "task", fields: { title: "Repot cactus", date: "2026-09-30" } },
                                              { intent: 1, op: "create", type: "task", fields: { title: "Took vitamins", date: "today", status: "completed" } } ])

    assert_predicate Task.find_by(title: "Repot cactus").first_occurrence, :pending?
    assert_predicate Task.find_by(title: "Took vitamins").first_occurrence, :completed?
  end

  test "the per-turn context names the dates small models get wrong" do
    prompt = Assistant::Context.new(assistant_chat(@alice)).to_prompt

    assert_match "Today is Tuesday 2026-09-22", prompt
    assert_match "this Friday = 2026-09-25, next Friday = 2026-10-02", prompt
    assert_match "Therapies:\n- \"B12\" (collection_id #{@b12.id})", prompt
  end
end
