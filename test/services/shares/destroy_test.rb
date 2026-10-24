# frozen_string_literal: true

require "test_helper"

class Shares::DestroyTest < ActiveSupport::TestCase
  test "the share goes, then the person hears it and the kind's hook runs" do
    photo, bob, alice = uploads(:photo), profiles(:bob), profiles(:alice)

    assert_difference -> { alice.notifications.unshared.count }, 1 do
      Shares::Destroy.call(upload_shares(:photo_alice), by: bob)
    end

    assert_not UploadShare.exists?(upload_shares(:photo_alice).id)
    assert_equal([ "unshared", bob, "Alice" ], photo.upload_activities.last.then { [ _1.action, _1.profile, _1.data["with"] ] })
  end
end
