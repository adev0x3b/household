# frozen_string_literal: true

require "test_helper"

# The line a deletion card shows for what it deletes, in the user's words.
class Assistant::ProposalSummaryTest < ActiveSupport::TestCase
  setup { @alice = profiles(:alice) }

  def summary(record, scope: "day") = Assistant::ProposalSummary.for(record, scope: scope)

  test "a purchase is named after what was bought, on its day; a range after its analyte and unit" do
    assert_equal "Needles on September 25, 2026", summary(supply_purchase!(profile: @alice, name: "Needles", purchased_on: Date.new(2026, 9, 25)))
    assert_equal "Flour on September 24, 2026", summary(ingredient_purchase!(profile: @alice, purchased_on: Date.new(2026, 9, 24)))
    assert_equal "the reference range of Glucose (mg/dL)", summary(reference_ranges(:glucose_any))
    assert_equal "Glucose (every time it repeats)", summary(analytes(:glucose), scope: "series")
  end

  test "many records list the first ten, and say how many more" do
    supplies = 12.times.map { |i| supply_purchase!(profile: @alice, name: "Box #{i}").supply }
    line = Assistant::ProposalSummary.for_many(supplies, scope: "day")

    assert line.start_with?("these 12: Box 0, Box 1")
    assert line.end_with?("Box 9, …and 2 more")
    assert_equal "Box 0", Assistant::ProposalSummary.for_many(supplies.first(1), scope: "day")
  end
end
