# frozen_string_literal: true

require "test_helper"

class ProfilePolicyTest < ActiveSupport::TestCase
  setup do
    @owner = profiles(:alice) # owns households(:example)
    @member = profiles(:bob)
    @admin = profiles(:carol).tap { _1.update!(role: :admin) }
    @outsider = profiles(:outsider)
  end

  def allowed?(user, record, action) = ProfilePolicy.new(user, record).public_send(action)

  test "the admin removes anyone but themselves; the owner anyone of their household but themselves" do
    assert allowed?(@admin, @member, :destroy?)
    assert allowed?(@admin, @owner, :destroy?)
    assert allowed?(@admin, @outsider, :destroy?)
    assert_not allowed?(@admin, @admin, :destroy?)

    assert allowed?(@owner, @member, :destroy?)
    assert allowed?(@owner, @admin, :destroy?)
    assert_not allowed?(@owner, @owner, :destroy?)
    assert_not allowed?(@owner, @outsider, :destroy?)

    assert_not allowed?(@member, @owner, :destroy?)
    assert_not allowed?(@member, @admin, :destroy?)
  end

  test "a household with no owner (the demo's): nobody removes a member but the admin" do
    demo = demo_household
    alex, sam = demo.members.order(:id).first(2)

    assert_nil demo.owner
    assert_not allowed?(alex, sam, :destroy?)
    assert allowed?(@admin, sam, :destroy?)
  end

  test "a new link comes from who invited them or the admin; cancelling also from the owner" do
    invitation = Households::Invite.call(households(:example), inviter: @member, email: "erin@example.com").profile

    assert allowed?(@member, invitation, :renew_invitation?)
    assert allowed?(@admin, invitation, :renew_invitation?)
    assert_not allowed?(@owner, invitation, :renew_invitation?)

    assert allowed?(@member, invitation, :cancel_invitation?)
    assert allowed?(@admin, invitation, :cancel_invitation?)
    assert allowed?(@owner, invitation, :cancel_invitation?)
    assert_not allowed?(@outsider, invitation, :cancel_invitation?)

    assert_not allowed?(@admin, @member, :renew_invitation?), "a member has no invitation to renew"
  end

  test "a password link for a member: the admin or the owner; never who invited them, oneself or an invitation" do
    invited = Households::Invite.call(households(:example), inviter: @member, email: "erin@example.com").profile
    joined = Profile.accept_invitation!(invitation_token: invited.raw_invitation_token, username: "erin", password: "a-long-password", password_confirmation: "a-long-password")

    assert allowed?(@admin, joined, :password_link?)
    assert allowed?(@owner, joined, :password_link?)
    assert_not allowed?(@member, joined, :password_link?), "inviting someone gives no hold on their account"
    assert_not allowed?(profiles(:carol).tap { _1.update!(role: :user) }, joined, :password_link?)
    assert_not allowed?(@admin, @admin, :password_link?)
    assert_not allowed?(@admin, invited, :password_link?)
  end

  test "the people one reaches are one's household's; the admin reaches everyone" do
    member_sees = ProfilePolicy::Scope.new(@member, Profile).resolve
    assert_includes member_sees, @owner
    assert_not_includes member_sees, @outsider
    assert_includes ProfilePolicy::Scope.new(@admin, Profile).resolve, @outsider

    assert_equal [ households(:example) ], HouseholdPolicy::Scope.new(@member, Household).resolve.to_a
    assert_includes HouseholdPolicy::Scope.new(@admin, Household).resolve, households(:elsewhere)
  end

  test "one's own account is one's own to manage, and an open account's nobody's" do
    assert allowed?(@member, @member, :manage_account?)
    assert_not allowed?(@admin, @member, :manage_account?)
    assert_not allowed?(@owner, @member, :manage_account?)

    on_the_demo do
      alex = demo_household.members.find_by!(username: "alex.demo")
      assert_not allowed?(alex, alex, :manage_account?)
    end
  end
end
