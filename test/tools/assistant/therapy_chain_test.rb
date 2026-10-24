# frozen_string_literal: true

require "test_helper"

# "I'm on a therapy called B12; I bought … and I inject every Monday": the
# therapy, its purchases and the repeating dose are one request.
class Assistant::TherapyChainTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 2, 12)
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
  end

  teardown { travel_back }

  def therapies = Collection.where(profile: @profile).where.not(name: "B12")
  def medications = Medication.where(profile: @profile)

  test "a purchase for a therapy that doesn't exist yet creates it and links to it" do
    result = run_tool(:record_purchases, @chat, therapy: "Thyroid", payment_method: "card",
                                                items: [ { supply: "cobalamin", quantity: 18, unit: "ml", amount: 80 } ])

    assert_equal "saved", result[:data][:status], result.inspect
    therapy = therapies.sole
    assert_equal [ "Thyroid", "healthcare" ], [ therapy.name, therapy.section ]
    purchase = SupplyPurchase.where(collection_id: therapy.id).sole
    assert_equal "ml", purchase.supply.unit_label
  end

  test "the therapy is created once for several purchases and later calls" do
    run_tool(:record_purchases, @chat, therapy: "Thyroid", payment_method: "card",
                                       items: [ { supply: "syringes", quantity: 100, amount: 20 }, { supply: "needles", quantity: 200, amount: 20 } ])
    run_tool(:record_purchases, @chat, therapy: "thyroid", payment_method: "card", items: [ { supply: "gauze", quantity: 5, amount: 3 } ])

    assert_equal 1, therapies.count
    assert_equal 3, SupplyPurchase.where(collection_id: therapies.sole.id).count
  end

  test "a typo of an existing therapy links to it instead of creating another" do
    existing = Collection.create!(profile: @profile, name: "Methotrexate", section: "healthcare")
    result = run_tool(:record_purchases, @chat, therapy: "Methotrexat", payment_method: "card", items: [ { supply: "needles", quantity: 10, amount: 2 } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ existing ], therapies.to_a
    assert_equal existing.id, SupplyPurchase.last.collection_id
  end

  test "an injection without side and area isn't saved, while the therapy and purchases are" do
    run_tool(:record_purchases, @chat, therapy: "Thyroid", payment_method: "card", items: [ { supply: "needles", quantity: 10, amount: 2 } ])
    result = run_tool(:record_medication, @chat, name: "Cobalamin injection", kind: "injection", quantity: 0.14, unit: "ml",
                                                 date: "next Monday", repeat: "weekly", days: [ "monday" ], therapy: "Thyroid")

    assert_equal "needs_input", result[:data][:status], result.inspect
    assert_equal %w[medication.area medication.side], result[:data][:changes].sole[:missing]
    assert_equal 0, medications.count

    result = run_tool(:record_medication, @chat, area: "thigh", side: "left")

    assert_equal "saved", result[:data][:status], result.inspect
    series = medications.sole
    assert_equal therapies.sole.id, series.collection_id
  end

  test "an injection with no kind said is still asked for side and area" do
    result = run_tool(:record_medication, @chat, name: "Cobalamin injection", date: "next Monday", therapy: "Thyroid")

    assert_equal "needs_input", result.dig(:data, :status), result.inspect
  end

  test "undoing the purchase takes the new therapy away too" do
    result = run_tool(:record_purchases, @chat, therapy: "Thyroid", payment_method: "card", items: [ { supply: "needles", quantity: 10, amount: 2 } ])

    Assistant::ChangeSets::Undoer.call(Assistant::ChangeSet.find(result[:data][:change_set_id]))

    assert_empty therapies
    assert_empty SupplyPurchase.where(profile: @profile)
  end

  test "the full chain meets scenario 43's expectations" do
    run_tool(:record_purchases, @chat, therapy: "MTX", payment_method: "card",
                                       items: [ { supply: "methotrexate", quantity: 10, unit: "ml", amount: 60 }, { supply: "syringes", quantity: 100, amount: 20 },
                                                { supply: "needles", quantity: 200, amount: 20 } ])
    asked = run_tool(:record_medication, @chat, name: "Methotrexate injection", kind: "injection", quantity: 0.25, unit: "ml", date: "next Monday",
                                                days: [ "monday" ], therapy: "MTX", uses: [ { supply: "methotrexate", quantity: 0.25 }, { supply: "syringes" }, { supply: "needles" } ])
    assert_equal "needs_input", asked[:data][:status], asked.inspect
    saved = run_tool(:record_medication, @chat, area: "thigh", side: "left")
    assert_equal "saved", saved[:data][:status], saved.inspect

    expect = YAML.safe_load_file(Rails.root.join("eval/assistant/scenarios/43_therapy_with_supplies_and_weekly_dose.yml"), permitted_classes: [ Date ]).fetch("expect")
    assert_empty AssistantEval::Expectations.new(@profile).failures(expect)
  end

  test "purchases and a dose using them in one go: the dose waits for the purchases and gets every supply" do
    run_tool(:record_purchases, @chat, therapy: "Thyroid",
                                       items: [ { supply: "Cobalamin", quantity: 18, unit: "ml", amount: 80 }, { supply: "Syringes", quantity: 100, amount: 20 } ])
    result = run_tool(:record_medication, @chat, name: "Cobalamin", kind: "injection", area: "thigh", side: "left", quantity: 0.12, unit: "ml",
                                                 date: "next Monday", days: [ "monday" ], therapy: "Thyroid",
                                                 uses: [ { supply: "cobalamin", quantity: 0.12 }, { supply: "syringe" } ])

    assert_equal "needs_input", result[:data][:status], result.inspect
    assert_nil result[:data][:saved], "the dose isn't saved before the supplies it uses"
    assert_equal 0, medications.count

    result = run_tool(:record_purchases, @chat, payment_method: "card", items: [ { supply: "Cobalamin" }, { supply: "Syringes" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    series = medications.sole
    assert_equal [ [ "Cobalamin", 0.12 ], [ "Syringes", 1 ] ], series.details.supply_uses.map { |use| [ use.supply.name, use.quantity.to_f ] }.sort
  end

  test "the medication itself is a supply its dose uses, even when only the syringe is listed" do
    run_tool(:record_purchases, @chat, therapy: "Thyroid", payment_method: "card",
                                       items: [ { supply: "Methotrexate", quantity: 10, unit: "ml", amount: 60 }, { supply: "Syringes", quantity: 100, amount: 20 } ])
    result = run_tool(:record_medication, @chat, name: "methotrexate", kind: "injection", area: "thigh", side: "left", quantity: 0.25,
                                                 unit: "ml", date: "next Monday", days: [ "monday" ], uses: [ { supply: "syringe" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal [ "Methotrexate 0.25 ml", "Syringes × 1" ], result[:data][:saved].sole[:uses].sort
  end

  test "a dose in another unit than its supply leaves the supply alone" do
    run_tool(:record_purchases, @chat, payment_method: "card", items: [ { supply: "Methotrexate", quantity: 4, unit: "vials", amount: 60 } ])
    result = run_tool(:record_medication, @chat, name: "Methotrexate", kind: "injection", area: "thigh", side: "left", quantity: 0.25,
                                                 unit: "ml", date: "today")

    assert_equal "saved", result[:data][:status], result.inspect
    assert_nil result[:data][:saved].sole[:uses]
  end
end
