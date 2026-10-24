# frozen_string_literal: true

require "test_helper"

# A purchase is its buyer's to change, and also of whoever the therapy it
# was bought for is shared with (they restock it); only the buyer deletes it.
class SupplyPurchasePolicyTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob) # collections(:b12), Alice's, is shared with Bob
  end

  test "the buyer changes and deletes it; the therapy's sharer changes it; nobody else" do
    for_therapy = supply_purchase!(profile: @alice, name: "Needles", collection: collections(:b12))
    alone = supply_purchase!(profile: @alice, name: "Swabs")

    assert_predicate SupplyPurchasePolicy.new(@alice, alone), :destroy?
    assert_predicate SupplyPurchasePolicy.new(@bob, for_therapy), :update?
    assert_not SupplyPurchasePolicy.new(@bob, for_therapy).destroy?
    assert_not SupplyPurchasePolicy.new(@bob, alone).update?
  end
end
