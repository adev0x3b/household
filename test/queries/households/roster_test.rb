# frozen_string_literal: true

require "test_helper"

# Households::Roster: a household's people as its page lists them.
class Households::RosterTest < ActiveSupport::TestCase
  test "members by name, invitations with who sent them, and the viewer's invitations left" do
    household = households(:example)
    erin = Households::Invite.call(household, inviter: profiles(:alice), email: "erin@example.com").profile

    roster = Households::Roster.new(household, viewer: profiles(:alice))

    assert_equal household.members.by_name.to_a, roster.members
    assert_equal [ erin ], roster.invitations
    assert_equal profiles(:alice), roster.invitations.first.invited_by
    assert_equal household.profiles.count, roster.size
    assert_nil roster.invites_left, "no limit is set"
    assert_predicate roster, :room_to_invite?
    assert_not_includes roster.members, profiles(:outsider)
  end

  test "the viewer's invitations left under the installation's limit" do
    Platform::Setting.create!(invitations_per_member: 1)
    household = households(:example)
    Households::Invite.call(household, inviter: profiles(:alice), email: "erin@example.com")

    roster = Households::Roster.new(household, viewer: profiles(:alice))

    assert_equal 0, roster.invites_left
    assert_not roster.room_to_invite?
  end
end
