# frozen_string_literal: true

require "test_helper"

# After a password changes: the other browsers' push stops, their live
# connections close, a link to set it stops working, and a confirmed
# address hears of it.
class Profiles::AfterPasswordChangeTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup { @alice = profiles(:alice) }

  test "every other browser's push subscription goes; the one it was changed from stays" do
    here = push_subscription_for(@alice)
    elsewhere = push_subscription_for(@alice)
    bobs = push_subscription_for(profiles(:bob))

    Profiles::AfterPasswordChange.call(@alice, device: here.id)

    assert PushSubscription.exists?(here.id)
    assert_not PushSubscription.exists?(elsewhere.id)
    assert PushSubscription.exists?(bobs.id)
  end

  test "changed from a browser without push, all of them go" do
    push_subscription_for(@alice)

    Profiles::AfterPasswordChange.call(@alice)

    assert_not @alice.push_subscriptions.exists?
  end

  test "the person's live connections are closed, to come back only where still signed in" do
    assert_broadcasts("action_cable/#{@alice.to_gid_param}", 1) { Profiles::AfterPasswordChange.call(@alice) }
  end

  test "a link to set the password stops working, even one made while it changed, after the person's row was read" do
    read_before = Profile.find(@alice.id)
    token = Profile.find(@alice.id).short_password_link_token!

    Profiles::AfterPasswordChange.call(read_before)

    assert_nil Profile.with_reset_password_token(token)
  end

  test "a confirmed address hears of it where mail goes out; an address not confirmed doesn't" do
    with_relay { Profiles::AfterPasswordChange.call(@alice) }
    assert_not OutgoingEmail.exists?

    @alice.update!(email_confirmed_at: Time.current)
    Profiles::AfterPasswordChange.call(@alice)
    assert_not OutgoingEmail.exists?, "no mail goes out"

    with_relay { Profiles::AfterPasswordChange.call(@alice) }
    notice = OutgoingEmail.sole
    assert_equal "password_changed", notice.kind
    assert_equal({ "to" => "alice@example.com" }, notice.data, "to the address confirmed now, whatever takes over before it goes")
  end
end
