# frozen_string_literal: true

require "test_helper"

class SupplyTest < ActiveSupport::TestCase
  test "a dose draws from the person's own supplies and those bought for a therapy shared with them, by name" do
    needles = supply_purchase!(profile: profiles(:alice), name: "Needles", collection: collections(:b12)).supply
    gauze = supply_purchase!(profile: profiles(:alice), name: "Gauze").supply
    pads = supply_purchase!(profile: profiles(:bob), name: "Alcohol pads").supply

    assert_equal [ gauze, needles ], Supply.choices_for(profiles(:alice)).to_a
    assert_equal [ pads, needles ], Supply.choices_for(profiles(:bob)).to_a
  end

  test "a supply a medication plans to use can't be deleted; once none does, it goes with what doses drew from it" do
    purchase = supply_purchase!(profile: profiles(:alice), name: "Syringe")
    dose = medication!(profile: profiles(:alice), date: Date.current)
    use = dose.event.details.supply_uses.create!(supply: purchase.supply, quantity: 1)
    dose.complete!

    assert_not purchase.supply.destroy
    assert_predicate purchase.supply.errors[:base], :present?
    assert SupplyConsumption.exists?(supply_id: purchase.supply_id), "nothing is taken from it while it stays"

    use.destroy!
    assert purchase.reload.supply.destroy
    assert_not SupplyPurchase.exists?(purchase.id)
    assert_not SupplyConsumption.exists?(supply_id: purchase.supply_id)
  end
end
