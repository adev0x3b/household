# frozen_string_literal: true

require "test_helper"

class SupplyUseTest < ActiveSupport::TestCase
  test "a planned use names a supply once per details row with a positive quantity" do
    purchase = supply_purchase!(profile: profiles(:alice), name: "Needles")
    details = events(:cobalamin).details

    use = details.supply_uses.create!(supply: purchase.supply, quantity: 1)
    assert_not SupplyUse.new(medication_details_id: details.id, supply: purchase.supply, quantity: 1).valid?, "once per supply"
    assert_not SupplyUse.new(medication_details_id: details.id, supply: purchase.supply, quantity: 0).valid?

    assert_equal [ [ purchase.supply_id, "1.0" ] ], details.uses_list
    details.replace_uses!([ [ purchase.supply_id, "2" ] ])
    assert_equal [ [ purchase.supply_id, "2.0" ] ], details.reload.uses_list
    assert_not SupplyUse.exists?(use.id)
  end

  test "a day's override row inherits the series' uses until it has its own" do
    purchase = supply_purchase!(profile: profiles(:alice), name: "Needles")
    event = events(:cobalamin)
    event.details.supply_uses.create!(supply: purchase.supply, quantity: 1)

    day = event.occurrence_on(Date.new(2026, 3, 9))
    day.write_details!(quantity: 1)
    assert_equal [ [ purchase.supply_id, "1.0" ] ], day.details.uses_list

    day.own_details.supply_uses.create!(supply: purchase.supply, quantity: 3)
    assert_equal [ [ purchase.supply_id, "3.0" ] ], day.reload.details.uses_list
  end
end
