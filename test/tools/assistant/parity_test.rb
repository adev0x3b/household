# frozen_string_literal: true

require "test_helper"

# Small things the forms could do and the assistant couldn't: a range for one
# sex, a pack's expiry and opening dates, renaming an analyte, a supply's
# low-stock warning.
class Assistant::ParityTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12)
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
  end

  teardown { travel_back }

  test "a reference range for one sex" do
    result = run_tool(:set_reference_ranges, @chat, ranges: [ { analyte: "Cobalamin", unit: "pg/mL", low: 30, high: 400, sex: "female" } ])

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal "female", ReferenceRange.where(analyte: @profile.analytes).sole.sex
  end

  test "a pack's expiry and opening dates are kept with the purchase" do
    result = run_tool(:record_purchases, @chat, items: [ { supply: "Cobalamin vial", quantity: 1, amount: 32, expires_on: "2027-03-31",
                                                           opened_on: "today" } ], payment_method: "card", date: "today")

    assert_equal "saved", result[:data][:status], result.inspect
    purchase = SupplyPurchase.where(profile: @profile).sole
    assert_equal [ Date.new(2027, 3, 31), Date.new(2026, 9, 24) ], [ purchase.expires_on, purchase.opened_on ]
  end

  test "an analyte can be renamed, only by its owner" do
    analyte = Analyte.create!(profile: @profile, name: "Vit D")

    result = run_tool(:update_record, @chat, type: "analyte", ref: "Vit D", changes: { name: "Vitamin D" })

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal "Vitamin D", analyte.reload.name
    assert_not AnalytePolicy.new(profiles(:alice), analyte).update?
  end

  test "a supply's low-stock warning" do
    AssistantEval::Seeds.b12_injection_series(@profile)

    result = run_tool(:update_record, @chat, type: "supply", ref: "needles", changes: { low_stock_threshold: 20 })

    assert_equal "saved", result[:data][:status], result.inspect
    assert_equal 20, Supply.find_by!("lower(name) = 'needles'").low_stock_threshold.to_i
  end
end
