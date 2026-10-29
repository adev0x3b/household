# frozen_string_literal: true

require "test_helper"

# A link by mail for a forgotten password: queued only for someone who may
# have one, one at a time, within the limits; nothing tells the asker which.
class Profiles::RequestPasswordLinkTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice).tap { _1.update!(email_confirmed_at: 1.day.ago) }
  end

  def request(profile = @alice, **) = with_relay { Profiles::RequestPasswordLink.call(profile, **) }

  test "queues a link for someone who has joined, at the address they confirmed" do
    assert request
    assert_equal [ [ @alice.id, "password_link", "queued" ] ], OutgoingEmail.pluck(:profile_id, :kind, :status)
  end

  test "never for the admin, an open account, an address not confirmed, an invitation, or where nothing is mailed" do
    assert_not request(profiles(:bob))
    assert_not Profiles::RequestPasswordLink.call(@alice), "no relay set"
    assert_not with_relay("OUTGOING_MAIL" => "off") { Profiles::RequestPasswordLink.call(@alice) }
    @alice.admin!
    assert_not request
    @alice.user!
    with_env("OPEN_ACCOUNTS" => @alice.username) { assert_not request }

    invited = Profile.invite!({ email: "erin@example.com", household: households(:example) }, @alice) { _1.skip_invitation = true }
    invited.update_columns(email_confirmed_at: 1.day.ago)
    assert_not request(invited)
    assert_empty OutgoingEmail.all
  end

  test "one at a time: none while one is on its way, or out and still working" do
    assert request
    assert_not request

    OutgoingEmail.update_all(status: :sent)
    @alice.short_password_link_token!
    assert_not request

    travel Profile::SHORT_PASSWORD_LINK_FOR + 1.second
    assert request
  end

  test "three a day for one person, two an hour and ten a day for the installation, every request counted" do
    bob = profiles(:bob).tap { _1.update!(email_confirmed_at: 1.day.ago) }
    asked = ->(profile, at) { OutgoingEmail.create!(profile:, kind: :password_link, status: :dropped, not_before: at, expires_at: at, created_at: at) }

    3.times { asked.call(@alice, 5.hours.ago) }
    assert_not request
    assert request(bob)

    asked.call(bob, 10.minutes.ago)
    OutgoingEmail.where(status: :queued).update_all(status: :sent)
    assert_not request(profiles(:carol).tap { _1.update!(email_confirmed_at: 1.day.ago) }), "two this hour already"

    travel 1.hour
    6.times { asked.call(profiles(:carol), 2.hours.ago) }
    assert_not request(profiles(:carol)), "ten today already"
  end
end
