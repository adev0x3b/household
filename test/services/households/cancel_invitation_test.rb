# frozen_string_literal: true

require "test_helper"

class Households::CancelInvitationTest < ActiveSupport::TestCase
  test "an invitation taken back is gone, and gives its inviter the invitation back" do
    Platform::Setting.create!(invitations_per_member: 5)
    household = households(:example)
    invitation = Households::Invite.call(household, inviter: profiles(:alice), email: "erin@example.com").profile
    left = household.invites_left_for(profiles(:alice))

    Households::CancelInvitation.call(invitation)

    assert_not Profile.exists?(invitation.id)
    assert_equal left + 1, household.invites_left_for(profiles(:alice))
  end

  test "a member can't be cancelled like an invitation" do
    assert_raises(ArgumentError) { Households::CancelInvitation.call(profiles(:bob)) }
    assert Profile.exists?(profiles(:bob).id)
  end
end
