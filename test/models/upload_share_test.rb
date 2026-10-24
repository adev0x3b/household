# frozen_string_literal: true

require "test_helper"

class UploadShareTest < ActiveSupport::TestCase
  test "a whole file, with a housemate who isn't its owner, once" do
    lease = uploads(:lease)

    assert_predicate lease.upload_shares.build(profile: profiles(:bob)), :valid?
    assert_not lease.upload_shares.build(profile: profiles(:alice)).valid?, "not with the owner"
    outsider = lease.upload_shares.build(profile: profiles(:outsider))
    assert_not outsider.valid?
    assert outsider.errors.of_kind?(:profile, :outside_household)
    assert_not uploads(:photo).upload_shares.build(profile: profiles(:alice)).valid?, "not twice"

    half = uploads(:backup).upload_shares.build(profile: profiles(:bob))
    assert_not half.valid?
    assert half.errors.of_kind?(:upload, :not_ready)
  end
end
