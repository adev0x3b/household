# frozen_string_literal: true

require "test_helper"

class Households::RenewInvitationTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @first = Households::Invite.call(households(:example), inviter: @alice, email: "erin@example.com")
  end

  test "a new link works and the old one doesn't; the invitation stays its first inviter's" do
    renewed = Households::RenewInvitation.call(@first.profile.reload, by: profiles(:bob))

    assert_predicate renewed, :success?
    assert_nil Profile.find_by_invitation_token(@first.token, true)
    assert_equal @first.profile, Profile.find_by_invitation_token(renewed.token, true)
    assert_equal @alice, @first.profile.reload.invited_by
  end

  test "a member has nothing to renew" do
    assert_raises(ArgumentError) { Households::RenewInvitation.call(profiles(:bob), by: @alice) }
  end
end
