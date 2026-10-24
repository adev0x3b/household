# frozen_string_literal: true

require "test_helper"

# What the bar on every page says about its person, read once per request.
class Navbar::FactsTest < ActiveSupport::TestCase
  setup do
    @bob = profiles(:bob)
    @alice = profiles(:alice)
  end

  test "counts the person's unread notifications and names their devices with push on" do
    Notifications::Deliver.call(recipient: @bob, kind: :shared, subject: recipes(:roast_chicken), actor: @alice)
    @bob.push_subscriptions.create!(endpoint: "https://push.example/bob", origin: "https://household.example",
                                    p256dh_key: "p256dh", auth_key: "auth")

    facts = Navbar::Facts.for(@bob)

    assert_equal 1, facts.unread_notifications
    assert_equal [ PushSubscription.digest("https://push.example/bob") ], facts.push_digests
  end

  test "counts the messages the person hasn't read and what waits for them on Links" do
    conversation = Conversation.direct_between(@alice, @bob)
    Messages::Send.call(conversation: conversation, sender: @alice, body: "Hi", images: [], client_id: SecureRandom.uuid, notify: false)
    Links::Request.call(from: @alice, to: @bob)

    facts = Navbar::Facts.for(@bob)

    assert_equal 1, facts.unread_messages
    assert_equal 1, facts.pending_links
  end
end
