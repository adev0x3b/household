# frozen_string_literal: true

require "test_helper"

# What the compiler makes of a call before anything is checked: a lab
# report's ranges and stray values put where they belong, a purchase of
# several things split into one each, a handle no create declares refused.
class Assistant::CompilerTest < ActiveSupport::TestCase
  setup { @alice = profiles(:alice) }

  # Each call its own chat, so its own change set.
  def compile(*operations)
    set = Assistant::ChangeSet.current_for(assistant_chat(@alice))
    set.merge!(intents: [ "test" ], operations: operations.map { { "intent" => 0 }.merge(_1.deep_stringify_keys) })
    set.save!
    Assistant::ChangeSets::Compiler.call(set).operations
  end

  def ranges(operations) = operations.select { _1.op == "set_range" }.map { _1.fields.slice("analyte", "unit", "range_text", "low", "high") }

  test "a lab report's ranges and stray values become ranges and values, however they were written" do
    values = { "Calcium" => "9.5", "Vitamin D" => "30" }
    report = { op: "create", type: "lab_test_result", fields: { date: "today", values: values } }

    by_name = compile(report.deep_merge(fields: { ranges: { "Calcium" => "8.5-10 mg/dL", "Vitamin D" => { "low" => 20, "high" => 50 } } }))
    assert_equal [ { "analyte" => "Calcium", "range_text" => "8.5-10 mg/dL", "unit" => "mg/dL" }, { "analyte" => "Vitamin D", "low" => 20, "high" => 50 } ], ranges(by_name)

    sentence = compile(report.deep_merge(fields: { reference_ranges: "Calcium 8.5-10. Vitamin D between 20 and 50 ng/mL" }))
    assert_equal([ "Calcium", "Vitamin D" ], ranges(sentence).map { _1["analyte"] })
    assert_equal "ng/mL", ranges(sentence).last["unit"]
    assert_equal [ nil ], ranges(compile(report.deep_merge(fields: { ranges: [ "between 1 and 2" ] }))).map { _1["analyte"] }, "names no analyte"

    stray = compile({ op: "create", type: "lab_test_result", fields: { date: "today", values: [ "Calcium 9.5 mg/dL" ], "Ferritin" => "40", "TSH" => { "low" => 0.4, "high" => 4 } } }).first
    assert_equal({ "Calcium" => "9.5 mg/dL", "Ferritin" => "40" }, stray.fields["values"])
  end

  test "a purchase of several things is one purchase each, an item's own details winning" do
    split = compile({ op: "create", type: "supply_purchase", fields: { items: "needles and syringes, swabs", payment_method: "card" } })
    assert_equal([ "needles", "syringes", "swabs" ], split.map { _1.fields["supply"] })
    assert(split.all? { _1.fields["payment_method"] == "card" })

    own = compile({ op: "create", type: "ingredient_purchase", fields: { items: [ { ingredient: "Rice", quantity: 2 }, "Beans" ], quantity: 1 } })
    assert_equal([ [ "Rice", 2 ], [ "Beans", 1 ] ], own.map { _1.fields.values_at("ingredient", "quantity") })
  end

  test "a handle no create in the change declares is refused" do
    update = compile({ op: "update", type: "task", ref: "$nowhere", fields: { title: "x" } }).sole
    assert_includes update.problems, "$nowhere is not the \"as\" of any create in this change"
  end
end
