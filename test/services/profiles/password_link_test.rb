# frozen_string_literal: true

require "test_helper"

# Profiles::PasswordLink: a link that sets someone's password, and the
# person told at once that it exists, on their phone too.
class Profiles::PasswordLinkTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @bob = profiles(:bob)
  end

  test "the person is told who made it, in their own language, with a push that wakes the phone" do
    @bob.update!(locale: "it")
    push_subscription_for(@bob)

    result = nil
    with_push_keys do
      assert_enqueued_jobs(1, only: Notifications::PushJob) { result = Profiles::PasswordLink.call(@bob, by: @alice) }
    end

    assert_predicate @bob.reload, :reset_password_period_valid?
    assert_predicate result.token, :present?
    notification = @bob.notifications.sole
    assert_predicate notification, :password_link_made?
    assert_equal @alice, notification.actor
    assert_predicate notification, :urgent?
    wording = Notifications::Wording.new(notification)
    I18n.with_locale(:it) do
      assert_equal "#{@alice.display_name} ha creato un link per impostare la tua password", wording.title
      assert_match(/entrare come te/, wording.detail)
    end
  end

  test "an invitation still waiting gets no link, and nobody is told" do
    invitation = Households::Invite.call(households(:example), inviter: @alice, email: "erin@example.com").profile

    assert_raises(ArgumentError) { Profiles::PasswordLink.call(invitation, by: @alice) }
    assert_empty invitation.notifications
  end
end
