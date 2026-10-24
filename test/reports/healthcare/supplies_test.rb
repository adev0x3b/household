# frozen_string_literal: true

require "test_helper"

class Reports::Healthcare::SuppliesTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
  end

  test "days left come from recent use, with severity bands" do
    purchase = supply_purchase!(profile: @profile, name: "Syringes", quantity: 10)
    dose = medication!(profile: @profile, date: Date.current - 2, status: :completed)
    SupplyConsumption.create!(supply: purchase.supply, supply_purchase: purchase, occurrence: dose, quantity: 30, consumed_at: 2.days.ago)
    # 30 used in the last 30 days → 1/day; 10 left → 10 days → critical

    row = report.runway_rows.sole

    assert_equal 10, row.days_left
    assert_equal :critical, row.severity
    assert_equal purchase.supply.projected_depletion_date, row.depletion_date
  end

  test "a running series' planned uses set the pace" do
    purchase = supply_purchase!(profile: @profile, name: "Vials", quantity: 20)
    event = series!("Medication", profile: @profile, starts_on: Date.current - 1, rrule: "FREQ=DAILY", title: "Cobalamin")
    event.details.supply_uses.create!(supply: purchase.supply, quantity: 2)
    # 2 a day → 20 left lasts about 10 days (the schedule's window counts both ends)

    assert_in_delta 10, report.runway_rows.sole.days_left, 1
  end

  test "a purchase in a collection shared with the viewer counts; a stranger's doesn't" do
    therapy = Collection.create!(profile: profiles(:bob), name: "B12")
    CollectionShare.create!(collection: therapy, profile: @profile)
    supply_purchase!(profile: profiles(:bob), name: "Shared vials", collection: therapy)
    supply_purchase!(profile: profiles(:alice), name: "Not mine")

    assert_equal([ "Shared vials" ], report.runway_rows.map { |row| row.supply.name })
  end

  test "no usage means no estimate rather than forever" do
    supply_purchase!(profile: @profile, name: "Gauze")

    assert_equal :unknown, report.runway_rows.sole.severity
  end

  test "low stock is critical even without a rate" do
    supply_purchase!(profile: @profile, name: "Alcohol wipes", quantity: 2, threshold: 5)

    assert_equal :critical, report.runway_rows.sole.severity
  end

  test "lists batches with stock that expire within 30 days" do
    supply_purchase!(profile: @profile, name: "Cobalamin", expires_on: Date.current + 10)
    supply_purchase!(profile: @profile, name: "Needles", expires_on: Date.current + 90)
    supply_purchase!(profile: @profile, name: "Empty vial", expires_on: Date.current + 5, remaining: 0)

    assert_equal([ "Cobalamin" ], report.expiring_rows.map { |row| row.supply.name })
  end

  private

  def report
    Reports::Healthcare::Supplies.new(audience: audience_for(@profile))
  end
end
