# frozen_string_literal: true

require "test_helper"

class Households::InviteTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @household = households(:example)
    @alice = profiles(:alice)
  end

  def invite(email, inviter: @alice, household: @household, **more)
    Households::Invite.call(household, inviter: inviter, email: email, **more)
  end

  test "an invitation is a profile of the household with no username yet and a link token, never an email" do
    result = nil
    assert_no_emails { result = invite(" Erin@Example.com ", first_name: "Erin") }

    assert_predicate result, :success?
    profile = result.profile
    assert_equal [ @household, "erin@example.com", "Erin", nil, @alice ], [ profile.household, profile.email, profile.first_name, profile.username, profile.invited_by ]
    assert_predicate profile, :invitation_pending?
    assert_equal profile, Profile.find_by_invitation_token(result.token, true)
    assert_empty Analyte.where(profile: profile)
  end

  test "someone invited is not a housemate until they accept" do
    profile = invite("erin@example.com").profile
    assert_not_includes @alice.housemates, profile

    accepted = Profile.accept_invitation!(invitation_token: profile.raw_invitation_token, username: "erin", password: "a-long-password", password_confirmation: "a-long-password")

    assert_empty accepted.errors
    assert_includes @alice.housemates, accepted
  end

  test "accepting needs a username" do
    profile = invite("erin@example.com").profile
    accepted = Profile.accept_invitation!(invitation_token: profile.raw_invitation_token, password: "a-long-password", password_confirmation: "a-long-password")

    assert accepted.errors.of_kind?(:username, :blank)
    assert_predicate profile.reload, :invitation_pending?
  end

  test "with no limits set, a member invites as many people as they like" do
    6.times { |n| assert_predicate invite("guest#{n}@example.com"), :success? }

    assert_nil @household.invites_left_for(@alice)
    assert_nil @household.places_left
    assert_not @household.full?
  end

  test "a member has the installation's invitations into their household; one cancelled is given back" do
    Platform::Setting.create!(invitations_per_member: 5)
    invitations = 5.times.map { |n| invite("guest#{n}@example.com") }
    assert invitations.all?(&:success?)
    assert_equal 0, @household.invites_left_for(@alice)

    refused = nil
    assert_no_emails { refused = invite("guest5@example.com") }
    assert_not refused.success?
    assert refused.profile.errors.of_kind?(:base, :no_invites_left)
    assert_equal [ "can't be invited: you've used your 5 invitations" ], refused.profile.errors[:base]
    assert_not Profile.exists?(email: "guest5@example.com")

    assert_predicate invite("other@example.com", inviter: profiles(:bob)), :success?, "everyone has their own five"

    Households::CancelInvitation.call(invitations.first.profile)
    assert_predicate invite("guest5@example.com"), :success?
  end

  test "a household holds the installation's size, invitations included" do
    Platform::Setting.create!(household_size: 20)
    16.times { |n| Profile.create!(household: @household, username: "member#{n}", email: "member#{n}@example.com", password: "a-long-password") }
    assert_equal 1, @household.invites_left_for(@alice)
    assert_predicate invite("last@example.com"), :success?

    refused = invite("one-too-many@example.com")
    assert refused.profile.errors.of_kind?(:base, :household_full)
    assert_equal [ "can't be invited: the household already has 20 people" ], refused.profile.errors[:base]
    assert_predicate @household, :full?
  end

  test "a size lowered below a household's people removes nobody, and lets nobody else in" do
    people = @household.profiles.count
    Platform::Setting.create!(household_size: people - 1)

    assert_predicate @household, :full?
    assert_equal 0, @household.invites_left_for(@alice)
    assert invite("erin@example.com").profile.errors.of_kind?(:base, :household_full)
    assert_equal people, @household.profiles.count
  end

  test "the admin invites into another household without spending their own" do
    Platform::Setting.create!(invitations_per_member: 5)
    admin = profiles(:alice).tap { |profile| profile.update!(role: :admin) }
    6.times { |n| assert_predicate invite("guest#{n}@example.com", inviter: admin, household: households(:elsewhere)), :success? }

    assert_equal 5, @household.invites_left_for(admin)
  end

  test "an address already known is refused the same way wherever it is; a bad one, or a list of them, too" do
    theirs = invite("erin@example.com", inviter: profiles(:outsider), household: households(:elsewhere)).profile

    [ "erin@example.com", profiles(:outsider).email, profiles(:bob).email ].each do |email|
      refused = invite(email)
      assert refused.profile.errors.of_kind?(:email, :taken), email
    end
    assert_equal households(:elsewhere), theirs.reload.household
    assert invite("not an email").profile.errors.of_kind?(:email, :invalid)
    assert invite("erin@example.com,bob").profile.errors.of_kind?(:email, :invalid), "one mailbox, never a list"
  end

  test "inviting someone already waiting here makes a new link and ends the old one, still the first inviter's" do
    first = invite("erin@example.com")
    again = invite("erin@example.com", inviter: profiles(:bob))

    assert_equal 1, Profile.where(email: "erin@example.com").count
    assert_not_equal first.token, again.token
    assert_nil Profile.find_by_invitation_token(first.token, true)
    assert_equal first.profile, Profile.find_by_invitation_token(again.token, true)
    assert_equal @alice, first.profile.reload.invited_by
  end
end
