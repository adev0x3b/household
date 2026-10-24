# frozen_string_literal: true

require "test_helper"

# The draft pipeline inside create operations: reading the shapes models
# send, and what a record still needs.
class Assistant::DraftsTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    travel_to Time.zone.local(2026, 9, 23, 12)
  end

  teardown { travel_back }

  def evaluate(kind, payload)
    draft = Assistant::Draft.new(kind: kind, profile: @alice)
    draft.merge_payload(payload)
    Assistant::DraftEvaluator.call(draft, profile: @alice)
  end

  test "an appointment needs its time, and a mentioned fee needs how it's paid" do
    draft = evaluate("appointment", appointment: { counterpart: "Moretti", date: "2026-09-25" }, transaction: { amount: "50" })

    assert_equal %w[appointment.start_time transaction.payment_method], draft.missing.pluck("field")
  end

  test "a purchase always needs its cost; derived stock is never asked" do
    assert_equal %w[supply_purchase.quantity_purchased transaction.amount transaction.payment_method],
                 evaluate("supply_purchase", supply_purchase: { supply_name: "Needles" }).missing.pluck("field")
  end

  test "a grocery purchase needs only a quantity; a price brings in the payment" do
    assert_equal %w[ingredient_purchase.quantity],
                 evaluate("ingredient_purchase", ingredient_purchase: { ingredient_name: "Flour" }).missing.pluck("field")
    assert_empty evaluate("ingredient_purchase", ingredient_purchase: { ingredient_name: "Flour", quantity: "1" }).missing
    assert_equal %w[transaction.payment_method],
                 evaluate("ingredient_purchase", ingredient_purchase: { ingredient_name: "Flour", quantity: "1" },
                                                 transaction: { amount: "2" }).missing.pluck("field")
  end

  test "a grocery purchase in a unit that can't convert reports the unit" do
    draft = evaluate("ingredient_purchase", ingredient_purchase: { ingredient_name: "Flour", quantity: "2", unit_name: "pcs" })

    assert_equal [ "ingredient_purchase.unit" ], draft.missing.pluck("field")
  end

  test "grocery purchase fields are read under the names models use" do
    assert_equal({ "ingredient_purchase" => { "ingredient_name" => "Flour", "quantity" => "1", "unit_name" => "kg" },
                   "transaction" => { "amount" => "2" } },
                 Assistant::Draft.normalize_payload("ingredient_purchase", "ingredient" => "Flour", "quantity" => "1", "unit" => "kg", "price" => "2"))
  end

  test "flat and misfiled payloads land in the right sections" do
    assert_equal({ "appointment" => { "counterpart" => "Moretti", "date" => "2026-09-25", "start_time" => "11:00" },
                   "transaction" => { "amount" => "50", "payment_method" => "card" } },
                 Assistant::Draft.normalize_payload("appointment", "doctor" => "Moretti", "date" => "2026-09-25", "time" => "11:00",
                                                                   "amount" => "50", "appointment" => { "payment_method" => "card" }))
    assert_equal({ "supply_purchase" => { "supply_name" => "needles", "quantity_purchased" => "100" } },
                 Assistant::Draft.normalize_payload("supply_purchase", "supply" => "100 needles"))
  end

  test "fields with nothing of the kind's own stay in their sections, and a collection named is the therapy" do
    assert_equal({ "therapy" => "B12" }, Assistant::Draft.normalize_payload("task", "collection" => "B12"))
    assert_equal({ "transaction" => { "amount" => "5", "title" => "Parking" }, "therapy" => "B12" },
                 Assistant::Draft.normalize_payload("transaction", "transaction" => { "amount" => "5" }, "title" => "Parking", "therapy" => "B12"))
    assert_equal({ "therapy" => "B12" }, Assistant::Draft.normalize_payload("transaction", "therapy" => "B12"))
  end

  test "a supply named in an object of its own is read as the purchase's fields" do
    assert_equal({ "supply_purchase" => { "supply_name" => "Needles", "quantity_purchased" => 100, "supply_unit" => "pcs" } },
                 Assistant::Draft.normalize_payload("supply_purchase", "supply" => { "name" => "Needles", "quantity" => 100, "unit" => "pcs" }))
  end

  test "amounts, enum values and dates are read the way people write them" do
    assert_equal(%w[50 50.00 12.50 1250.50 1250.50 32], [ "50", "50,00", "12,50", "1.250,50", "1,250.50", "32 euros" ].map { |v| Assistant::Normalize.amount(v) })
    assert_equal "bank_transfer", Assistant::Normalize.enum("Bank transfer")
    assert_equal "2026-09-16", Assistant::Draft.normalize_payload("lab_test_result", "occurrence_date" => "a week ago").dig("lab_test_result", "date")
    assert_equal "2026-09-16", Assistant::Draft.normalize_payload("lab_test_result", "date" => "a week ago").dig("lab_test_result", "date")
    assert_equal "when it suits", Assistant::Draft.normalize_payload("task", "date" => "when it suits").dig("task", "date"),
                 "words that aren't a date are left for the checks to report"
  end

  test "therapies are found by name, only among accessible collections" do
    shared = Assistant::Draft.new(kind: "supply_purchase", profile: profiles(:bob), payload: { "therapy" => "b12" })
    assert_equal collections(:b12).id, Assistant::DraftBuilder.for(shared, profile: profiles(:bob)).collection_id

    stranger = Assistant::Draft.new(kind: "supply_purchase", profile: profiles(:carol), payload: { "therapy" => "B12" })
    assert_nil Assistant::DraftBuilder.for(stranger, profile: profiles(:carol)).collection_id
  end

  test "a calendar kind's draft is the first day of a new series, its fields where they belong" do
    draft = Assistant::Draft.new(kind: "appointment", profile: @alice)
    draft.merge_payload("doctor" => "Moretti", "date" => "2026-09-25", "time" => "11:00", "location" => "Clinic", "kind" => "work")
    day = Assistant::DraftBuilder.for(draft, profile: @alice).record

    assert_predicate day, :new_record?
    assert_equal Date.new(2026, 9, 25), day.date
    assert_instance_of Appointment, day.event
    assert_equal [ "Moretti", "work", "Clinic", "11:00" ], [ day.details.counterpart, day.details.kind, day.location, day.formatted_start_time ]
    assert_equal "Appointment with Moretti", day.event.title
  end

  test "a medication taken at set times builds its slots, the first day at the first one" do
    draft = Assistant::Draft.new(kind: "medication", profile: @alice)
    draft.merge_payload("name" => "Metformin", "kind" => "pill", "date" => "2026-09-25", "recurrence" => { "frequency" => "daily", "slots" => %w[CV CM] })
    day = Assistant::DraftBuilder.for(draft, profile: @alice).record

    assert_equal [ [ "08:00", "CM" ], [ "19:30", "CV" ] ], day.event.slots
    assert_equal [ "08:00", "CM" ], [ day.time_string, day.anchor ]
    assert_equal "Metformin", day.event.title
  end

  test "supplies are found by id or name only among the profile's, else a new one of theirs" do
    needles = supply_purchase!(profile: @alice, name: "Needles").supply
    carol = profiles(:carol)
    builder = ->(section) { Assistant::DraftBuilder.for(Assistant::Draft.new(kind: "supply_purchase", profile: carol, payload: { "supply_purchase" => section }), profile: carol) }

    assert_nil builder.call("supply_id" => needles.id.to_s).supply
    named = builder.call("supply_name" => "Needles").supply
    assert_predicate named, :new_record?
    assert_equal carol, named.profile
    assert_equal needles, Assistant::DraftBuilder.for(Assistant::Draft.new(kind: "supply_purchase", profile: @alice, payload: { "supply_purchase" => { "supply_id" => needles.id.to_s } }), profile: @alice).supply
  end

  test "supply names match the catalog entry they clearly mean" do
    needles = supply_purchase!(profile: @alice, name: "Needles").supply
    supply_purchase!(profile: @alice, name: "Syringe 3ml")
    supply_purchase!(profile: @alice, name: "Syringe 5ml")

    assert_equal needles, Assistant::NameMatch.find(Supply.all, "Needles 25G")
    assert_nil Assistant::NameMatch.find(Supply.all, "syringe"), "two candidates: ambiguous"
  end

  test "the lab payload that was once saved empty now yields four values" do
    draft = Assistant::Draft.new(kind: "lab_test_result", profile: @alice)
    draft.merge_payload("title" => "B12 Blood Panel", "occurrence_date" => "2026-09-16",
                        "test_results" => { "Calcium" => "300", "Cobalamin" => "250 pg/mL", "Vitamin D" => "20", "Homocysteine" => "0,8" })

    assert_equal [ { "analyte_name" => "Calcium", "value" => "300" }, { "analyte_name" => "Cobalamin", "value" => "250", "unit_name" => "pg/mL" },
                   { "analyte_name" => "Vitamin D", "value" => "20" }, { "analyte_name" => "Homocysteine", "value" => "0.8" } ], draft.payload["entries"]
  end

  test "lab values sent as entries at the top level are read like any others" do
    assert_equal({ "entries" => [ { "analyte_name" => "Calcium", "value" => "9.5", "unit_name" => "mg/dL" } ] },
                 Assistant::Draft.normalize_payload("lab_test_result", "entries" => [ { "analyte" => "Calcium", "value" => "9.5 mg/dL" } ]))
  end

  test "a draft that still lacks something is never saved" do
    draft = evaluate("lab_test_result", "date" => "2026-09-16", "title" => "Panel")

    assert_no_difference -> { Event.count } do
      assert_raises(ArgumentError) { Assistant::DraftCommitter.call(draft, profile: @alice) }
    end
  end

  test "a lab result needs a value; checking it writes no analytes and matches existing ones" do
    assert_equal [ "lab_test_result.entries" ], evaluate("lab_test_result", "date" => "2026-09-16", "title" => "Panel").missing.pluck("field")

    vitamin_d = Analyte.create!(profile: @alice, name: "Vitamin D (25-OH)")
    assert_no_difference -> { Analyte.count + Unit.count } do
      draft = Assistant::Draft.new(kind: "lab_test_result", profile: @alice)
      draft.merge_payload("date" => "2026-09-16", "values" => { "Vitamin D" => "20 ng/mL", "Cobalamin" => "250" })
      builder = Assistant::DraftBuilder.for(draft, profile: @alice)
      Assistant::DraftEvaluator.call(draft, profile: @alice, builder: builder)
      assert_equal vitamin_d, builder.lab_entries.first.analyte
      assert_equal [ "Cobalamin" ], builder.new_analyte_names
    end
  end

  test "the same report logged again with another date is a possible duplicate" do
    result = lab_result!(profile: @alice, date: Date.new(2026, 9, 23), title: "Lab results", values: { "Cobalamin" => "250" })

    warning = evaluate("lab_test_result", "date" => "2026-09-16", "values" => { "Cobalamin" => "250" }).warnings.sole
    assert_equal result.id, warning.dig("existing", "id")
  end

  test "every kind a draft can be has its builder" do
    assert_equal Assistant::Draft::KINDS.sort, Assistant::DraftBuilder::KINDS.keys.sort
  end

  test "items are the same when their shared identifying fields agree" do
    same = ->(a, b) { Assistant::Draft.same_item?(a, b) }
    assert same.({}, { "counterpart" => "moretti" })
    assert same.({ "counterpart" => "moretti", "title" => "checkup" }, { "counterpart" => "moretti" })
    assert_not same.({ "counterpart" => "rossi" }, { "counterpart" => "moretti" })
    assert_not same.({ "supply_id" => "1" }, { "supply_name" => "syringes" })
  end
end
