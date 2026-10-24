# frozen_string_literal: true

require "test_helper"

# How an operation the model sent is read before anything else
# (Assistant::Operations.normalize), and when a later call is the same one
# (Operations.same?), so it merges into it rather than adds.
class Assistant::OperationsTest < ActiveSupport::TestCase
  def normalize(spec) = Assistant::Operations.normalize(spec)

  test "an op is read whatever its spelling: a range without an op, a type left out, fields at the top" do
    assert_equal({ "op" => "set_range", "type" => "reference_range", "fields" => { "analyte" => "TSH" } }, normalize(type: "normal range", fields: { analyte: "TSH" }))
    assert_equal "set_status", normalize(op: "Set Status", type: "task")["op"]
    assert_equal({ "op" => "delete", "ref" => 7, "fields" => { "scope" => "series" } }, normalize(op: "delete", id: 7, scope: "series"), "no type, its id as the ref, a stray key as a field")
  end

  test "operations apply in their phases, whatever order the model gave them" do
    build = ->(spec) { Assistant::Operations.build(spec, index: 0, context: nil) }
    given = [ { op: "delete", type: "task" }, { op: "share", type: "task" }, { op: "set_range" }, { op: "update", type: "task" },
              { op: "create", type: "task" }, { op: "merge", type: "analyte" }, { op: "uncomplete", type: "task" } ]

    applied = given.map(&build).sort_by(&:apply_order).map(&:op)

    assert_equal %w[create update merge set_range share uncomplete delete], applied
    assert_raises(ArgumentError) { build.(op: "fly").apply_order }
  end

  test "a create of a kind that can't be made is still named by its kind" do
    create = Assistant::Operations.build(normalize(op: "create", type: "spaceship"), index: 0, context: nil).compile

    assert_match "spaceship can't be created", create.problems.sole
    assert_equal "Spaceship", create.label
  end

  test "a later call is the same operation when it creates the same thing, or names the same record or range" do
    same = ->(a, b) { Assistant::Operations.same?(a, b) }

    assert same.({ op: "update", type: "task", ref: "Bins" }, { op: "update", type: "task", ref: "  bins " })
    assert_not same.({ op: "update", type: "task", ref: "Bins" }, { op: "complete", type: "task", ref: "Bins" })
    assert same.({ op: "delete", type: "task", fields: { all: true } }, { op: "delete", type: "task", fields: { all: true } })
    assert_not same.({ op: "delete", type: "task", fields: { all: true } }, { op: "delete", type: "task", fields: { query: "bins" } })
    assert same.({ op: "set_range", fields: { analyte: "TSH", unit: "mIU/L", low: 0.4 } }, { op: "set_range", fields: { analyte: "tsh", unit: "miu/l", high: 4 } })
    assert same.({ op: "create", type: "task", fields: { title: "Bins" } }, { op: "create", type: "task", fields: { date: "tomorrow" } }),
           "a follow-up naming nothing new belongs to the draft"
    assert_not same.({ op: "create", type: "task", fields: { title: "Bins" } }, { op: "create", type: "task", fields: { title: "Laundry" } })
    assert same.({ op: "create", type: "spaceship", fields: { name: "x" } }, { op: "create", type: "spaceship", fields: { name: "y" } }),
           "no kind, nothing to compare"
  end
end
