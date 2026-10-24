# frozen_string_literal: true

require "test_helper"

class LinkRemovalTest < ActiveSupport::TestCase
  test "removing a person ends their links, and what waited on them, and nothing else" do
    alice, bob, carol = profiles(:alice), profiles(:bob), profiles(:carol)
    link!(alice, bob)
    kept = link!(alice, carol)
    Links::Approvals::Hold.call(requester: bob, record: occurrences(:groceries_due), kind: :complete)

    Profiles::Destroy.call(bob)

    assert_equal [ kept ], Link.all.to_a
    assert_equal [ carol.id ], LinkGrant.distinct.pluck(:grantee_id) - [ alice.id ]
    assert_equal 0, LinkApproval.count
  end
end
