# frozen_string_literal: true

require "test_helper"

# The supplies a dose uses: stock goes down when it's taken, future doses of
# a new series inherit them, and a supply nobody bought is reported, not made up.
class Assistant::SupplyUsesTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12)
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
    AssistantEval::Seeds.b12_injection_series(@profile)
  end

  teardown { travel_back }

  def stock(name) = SupplyPurchase.where(profile: @profile).joins(:supply).where("lower(supplies.name) = ?", name).sum(:quantity_remaining).to_i
  def today_dose = days_of(Medication, @profile).find_by(date: Date.new(2026, 9, 24))

  test "taking today's dose with a needle and a syringe draws them from stock; Undo gives them back" do
    result = run_tool(:mark_done, @chat, type: "medication", ref: "cobalamin today",
                                         uses: [ { supply: "needle", quantity: 1 }, { supply: "syringe" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal "completed", today_dose.status
    assert_equal [ 99, 49 ], [ stock("needles"), stock("syringes") ]

    Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))
    assert_equal [ 100, 50 ], [ stock("needles"), stock("syringes") ]
    assert_nil today_dose, "the dose goes back to upcoming"
  end

  test "a vial bought in the same call as a first dose from it: the dose draws on it once the purchase is saved" do
    vial = { supply: "Heparin", quantity: 10, unit: "ml", date: "today", amount: 12, payment_method: "card" }
    dose = { title: "Heparin", kind: "drops", quantity: 0.5, unit: "ml", date: "today", status: "completed", uses: [ { supply: "needle" } ] }
    result = submit_changes(@chat, [ { op: "create", type: "supply_purchase", fields: vial }, { op: "create", type: "medication", fields: dose } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ 9, 99 ], [ stock("heparin"), stock("needles") ].map(&:round)
  end

  test "a new series with its supplies: each dose inherits them" do
    result = run_tool(:record_medication, @chat, name: "Metformin", kind: "pill", date: "today", taken: true, repeat: "daily",
                                                 uses: [ { supply: "Syringes", quantity: 2 } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal 48, stock("syringes")
    series = Medication.where(profile: @profile).order(:id).last
    tomorrow = series.occurrence_on(Date.new(2026, 9, 25))
    assert_equal([ [ "Syringes", 2 ] ], tomorrow.details.resolved_uses.map { |use| [ use.supply.name, use.quantity.to_i ] })
  end

  def series = Medication.where(profile: @profile).order(:id).first
  # What a dose plans to use (its own list, else its series').
  def uses_of(dose) = dose.details.resolved_uses.map { |use| [ use.supply.name, use.quantity.to_s("F").delete_suffix(".0") ] }.sort
  def needle_and_syringe = [ { supply: "needle" }, { supply: "syringe", quantity: 1 } ]

  test "supplies forgotten on a series: its doses use them from now on, and Undo takes them off" do
    result = run_tool(:update_record, @chat, type: "medication", ref: "cobalamin", uses: needle_and_syringe)

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ "Needles × 1", "Syringes × 1" ], result[:data][:saved].first[:uses].sort
    next_week = series.occurrence_on(Date.new(2026, 10, 1))
    assert_equal [ [ "Needles", "1" ], [ "Syringes", "1" ] ], uses_of(next_week)
    assert_equal [ 100, 50 ], [ stock("needles"), stock("syringes") ], "nothing is drawn before a dose is taken"
    assert_match "using Needles × 1, Syringes × 1", Assistant::ChangeSet.find(result[:data][:change_set_id]).display.first["summary"]

    Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))
    assert_empty uses_of(series.occurrence_on(Date.new(2026, 10, 1)))
  end

  test "a bare series ref on a day without a dose means its next one" do
    travel_to Time.zone.local(2026, 9, 26, 12)
    result = run_tool(:update_record, assistant_chat(@profile), type: "medication", ref: "event_id #{series.id}", uses: needle_and_syringe)

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ [ "Needles", "1" ], [ "Syringes", "1" ] ], uses_of(series.occurrence_on(Date.new(2026, 10, 1)))
  end

  test "uses inside changes, or by supply id, count too" do
    needles = Supply.find_by!(profile: @profile, name: "Needles")
    result = run_tool(:update_record, @chat, type: "medication", ref: "cobalamin", changes: { uses: [ { supply: needles.id.to_s, quantity: 2 } ] })

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ [ "Needles", "2" ] ], uses_of(series.occurrence_on(Date.new(2026, 10, 1)))
  end

  test "doses already taken keep what they drew; the series plans the new supplies, without splitting" do
    needles = Supply.find_by!(profile: @profile, name: "Needles")
    first = series.first_occurrence
    series.replace_uses_for!(first, [ [ needles.id, 1 ] ])
    first.complete!
    assert_equal 99, stock("needles")
    result = run_tool(:update_record, @chat, type: "medication", ref: "cobalamin", uses: [ { supply: "syringe" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal([ [ "Needles", "1" ] ], first.reload.supply_consumptions.map { |c| [ c.supply.name, c.quantity.to_i.to_s ] })
    assert_equal [ [ "Needles", "1" ] ], uses_of(first), "its own list stays"
    assert_equal [ [ "Syringes", "1" ] ], uses_of(series.occurrence_on(Date.new(2026, 10, 1)))
    assert_equal 1, Medication.where(profile: @profile).count
    assert_equal [ 99, 50 ], [ stock("needles"), stock("syringes") ]

    Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))
    assert_empty uses_of(series.occurrence_on(Date.new(2026, 10, 1)))
  end

  test "a taken dose's supplies corrected: its stock follows, and comes back on Undo" do
    dose = Medication.new(title: "Ibuprofen shot", starts_on: Date.new(2026, 9, 23), details_attributes: { kind: :injection, area: :arm, side: :left })
    Occurrences::Create.call(dose, by: @profile)
    dose.first_occurrence.complete!
    result = run_tool(:update_record, @chat, type: "medication", ref: "ibuprofen", uses: [ { supply: "needles", quantity: 2 } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal 98, stock("needles")
    Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))
    assert_equal 100, stock("needles")
  end

  test "a dose with a list of its own, taken with other supplies, gets its own list back on Undo" do
    series = Medication.find_by!(profile: @profile, title: "Cobalamin injection")
    syringes = @profile.supplies.find_by!(name: "Syringes")
    series.replace_uses_for!(series.occurrence_on(Date.new(2026, 9, 24)), [ [ syringes.id, 1 ] ])

    result = run_tool(:mark_done, @chat, type: "medication", ref: "cobalamin today", uses: [ { supply: "needle" } ])
    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ [ "Needles", "1" ] ], uses_of(today_dose)
    assert_equal [ 99, 50 ], [ stock("needles"), stock("syringes") ]

    Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))
    assert_predicate today_dose, :pending?
    assert_equal [ [ "Syringes", "1" ] ], uses_of(today_dose)
    assert_equal [ 100, 50 ], [ stock("needles"), stock("syringes") ]
  end

  test "supplies sent as a new dose of a medication that repeats: the call points at the series, dated or not" do
    [ { date: "2026-09-26" }, {} ].each do |date|
      result = run_tool(:record_medication, @chat, name: "Cobalamin", kind: "injection", uses: needle_and_syringe, **date)

      assert_equal false, result[:ok], result.inspect
      assert_match(/already repeats \(event_id #{series.id}\).*set_dose_supplies \(medication "Cobalamin injection", the same uses\); new days.*update_record/, result[:error])
    end
    assert_equal 1, Medication.where(profile: @profile).count
  end

  test "a dose of the series taken, sent as a new medication with its supplies, points at mark_done" do
    result = run_tool(:record_medication, @chat, name: "Cobalamin injection", kind: "injection", date: "2026-09-24", taken: true,
                                                 uses: needle_and_syringe)

    assert_equal false, result[:ok], result.inspect
    assert_match(/mark_done with type medication, ref "event_id #{series.id} on 2026-09-24" and the same uses/, result[:error])
    result = run_tool(:mark_done, @chat, type: "medication", ref: "event_id #{series.id} on 2026-09-24", uses: needle_and_syringe)
    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ 99, 49 ], [ stock("needles"), stock("syringes") ]
  end

  test "a second, separate medication of the same name still saves with confirm" do
    arguments = { name: "Cobalamin", kind: "pill", date: "2026-09-26", uses: needle_and_syringe }
    assert_equal false, run_tool(:record_medication, @chat, **arguments)[:ok]
    result = run_tool(:record_medication, @chat, **arguments, confirm: true)

    assert_equal "saved", result[:data][:status], result.inspect
  end

  test "a dose on a day off its series, without supplies, gets the series hint" do
    result = run_tool(:record_medication, @chat, name: "Cobalamin injection", kind: "injection", area: "thigh", side: "left", date: "2026-09-26")

    assert_not_equal "saved", result[:data][:status], result.inspect
    assert_match "already repeats", result.to_s
  end

  test "what a dose uses, sent as a purchase of one, fails pointing at set_dose_supplies; confirm buys it anyway" do
    arguments = { items: [ { supply: "Needles", quantity: 1 }, { supply: "Syringes", quantity: 1 } ] }
    result = run_tool(:record_purchases, @chat, **arguments)

    assert_equal false, result[:ok], result.inspect
    assert_match "Needles is already in stock and nothing about buying was given (no price)", result[:error]
    assert_match "call set_dose_supplies", result[:error]
    assert_equal "needs_input", run_tool(:record_purchases, @chat, **arguments, confirm: true)[:data][:status], "then the price is asked"
  end

  test "more than a dose's worth without a price is still a purchase, with the hint leading the question" do
    result = run_tool(:record_purchases, @chat, items: [ { supply: "Needles", quantity: 20 } ])

    assert_equal "needs_input", result[:data][:status], result.inspect
    assert_match(/\ANOT SAVED YET\. Needles is already in stock.*set_dose_supplies with medication "Cobalamin injection"/, result[:data][:next])
  end

  test "set_dose_supplies: the supplies go on the series named, or on the only one there is" do
    [ { medication: "cobalamin" }, {} ].each do |named|
      result = run_tool(:set_dose_supplies, assistant_chat(@profile), uses: needle_and_syringe, **named)

      assert_equal "saved", result[:data][:status], result.inspect
      assert_equal [ [ "Needles", "1" ], [ "Syringes", "1" ] ], uses_of(series.occurrence_on(Date.new(2026, 10, 1)))
    end
  end

  test "set_dose_supplies: a medication still being created in the chat takes them (it waits for its injection site)" do
    result = run_tool(:record_medication, @chat, name: "Methotrexate", kind: "injection", quantity: 0.25, unit: "ml", date: "next Monday",
                                                 days: [ "monday" ])
    assert_equal "needs_input", result[:data][:status], result.inspect

    run_tool(:set_dose_supplies, @chat, medication: "methotrexate", uses: needle_and_syringe)
    result = run_tool(:record_medication, @chat, area: "thigh", side: "left")

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ "Needles × 1", "Syringes × 1" ], result[:data][:saved].sole[:uses].sort
  end

  test "set_dose_supplies: with several medications and none named, it asks which, naming them" do
    other = Medication.new(title: "Metformin", starts_on: Date.new(2026, 9, 25), details_attributes: { kind: :pill })
    Occurrences::Create.call(other, by: @profile, recurrence: { frequency: "daily", interval: 1 })
    result = run_tool(:set_dose_supplies, @chat, uses: needle_and_syringe)

    assert_equal false, result[:ok]
    assert_match(/which medication\? Give medication — one of: (Cobalamin injection, Metformin|Metformin, Cobalamin injection)/, result[:error])
  end

  test "supplies sent as a new medication named like a therapy (or not named) point at set_dose_supplies" do
    [ { name: "B12" }, {} ].each do |named|
      result = run_tool(:record_medication, @chat, kind: "injection", uses: needle_and_syringe, **named)

      assert_equal false, result[:ok], result.inspect
      assert_match "call set_dose_supplies with medication (Cobalamin injection)", result[:error]
    end
  end

  test "\"taken\" on a day the series has no dose isn't sent to mark_done" do
    result = run_tool(:record_medication, @chat, name: "Cobalamin injection", kind: "injection", date: "2026-09-26", taken: true,
                                                 uses: needle_and_syringe)

    assert_match "goes on it with set_dose_supplies", result[:error]
    assert_no_match "mark_done", result[:error]
  end

  test "a real purchase with its price gets no such hint" do
    result = run_tool(:record_purchases, @chat, payment_method: "card", items: [ { supply: "Needles", quantity: 100, amount: 12 } ])

    assert_equal "saved", result[:data][:status], result.inspect
  end

  test "a supply nobody has bought is reported, never created" do
    result = run_tool(:mark_done, @chat, type: "medication", ref: "cobalamin today", uses: [ { supply: "alcohol swab" } ])

    assert_match "no supply called alcohol swab", result.to_s
    assert_nil Supply.find_by("lower(name) = 'alcohol swab'")
    assert_nil today_dose
  end

  test "a full box of a supply in stock, without a price, is a purchase: only the price is asked" do
    result = run_tool(:record_purchases, @chat, items: [ { supply: "Needles", quantity: 100 } ])

    assert_equal "needs_input", result[:data][:status], result.inspect
    assert_no_match "set_dose_supplies", result.to_s
  end

  test "supplies for a therapy, with no medication that repeats, are left for the model to name one" do
    result = run_tool(:record_medication, assistant_chat(AssistantEval::Sandbox.profile!), name: "B12", kind: "injection", uses: needle_and_syringe)

    assert result[:ok], result.inspect
    assert_no_match "set_dose_supplies", result.to_s
  end

  test "supplies for a therapy's name still make a medication of that name with confirm" do
    arguments = { name: "B12", kind: "injection", date: "2026-09-26", area: "thigh", side: "left", uses: needle_and_syringe }
    assert_equal false, run_tool(:record_medication, @chat, **arguments)[:ok]
    result = run_tool(:record_medication, @chat, **arguments, confirm: true)

    assert result[:ok], result.inspect
    assert Medication.exists?(profile: @profile, title: "B12")
  end
end
