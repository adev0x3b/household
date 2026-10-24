# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class Messages::SendTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @alice, @bob, @carol = profiles(:alice), profiles(:bob), profiles(:carol)
    @chat = Conversation.household_conversation(households(:example))
  end

  test "a message goes to everyone's page, their list and their count; the sender's too" do
    bob_page = capture_turbo_stream_broadcasts([ @chat, @bob ]) do
      bob_pages = capture_turbo_stream_broadcasts([ @bob, :notifications ]) do
        alice_page = capture_turbo_stream_broadcasts([ @chat, @alice ]) do
          perform_enqueued_jobs(only: Conversations::BroadcastJob) do
            send_message(@chat, @alice, "dinner's ready")
          end
        end
        assert_equal(%w[append replace], alice_page.map { _1["action"] })
        assert_includes alice_page.first.to_html, "message--mine"
      end
      assert_equal([ "conversation-row-#{@chat.id}", ".messages-badge" ], bob_pages.map { _1["target"] || _1["targets"] })
      assert_includes bob_pages.first.to_html, "Alice: dinner's ready"
      assert_includes bob_pages.second.to_html, ">1<"
    end
    assert_includes bob_page.first.to_html, "message--theirs"
    assert_includes bob_page.first.to_html, "message__sender\">Alice<"
  end

  test "sending waits for nobody: the others' pages are pushed by a job, one conversation in order" do
    message = nil
    assert_no_turbo_stream_broadcasts([ @chat, @bob ]) do
      assert_enqueued_with(job: Conversations::BroadcastJob) { message = send_message(@chat, @alice, "dinner's ready") }
    end
    assert_equal "Conversations::BroadcastJob/Conversation/#{@chat.id}", Conversations::BroadcastJob.new("message_sent", message).concurrency_key,
                 "one conversation's pushes wait for each other"
    assert_equal "Conversations::BroadcastJob/Conversation/#{@chat.id}", Conversations::BroadcastJob.new("read", @chat, @bob).concurrency_key
  end

  test "a few seconds later, whoever hasn't seen it is told once per conversation, and pushed" do
    with_push_keys do
      push_subscription_for(@bob)

      message = send_message(@chat, @alice, "first", notify: true)
      @chat.participant_for(@carol).read_up_to!(message) # Carol had it open: read as it arrived
      assert_enqueued_with(job: Messages::NotifyJob, args: [ message.id ])

      perform_enqueued_jobs(only: Messages::NotifyJob)
      notification = @bob.notifications.message_received.sole
      assert_equal [ @alice, @chat, "Example", "Alice: first", "Alice wrote in Example" ],
                   [ notification.actor, notification.subject, notification.subject_title, wording_of(notification).detail, wording_of(notification).title ]
      assert_equal 0, @carol.notifications.count
      assert_enqueued_with(job: Notifications::PushJob)

      send_message(@chat, @alice, "second", notify: true)
      perform_enqueued_jobs(only: Messages::NotifyJob)
      assert_equal 1, @bob.notifications.count, "one line per conversation"
      assert_equal "Alice: second", wording_of(notification.reload).detail
      assert_equal 2, notification.data["unread"]
      assert_equal Rails.application.routes.url_helpers.conversation_path(@chat), Notifications::Destination.new(notification).path

      notification.mark_read!
      send_message(@chat, @alice, "third", notify: true)
      perform_enqueued_jobs(only: Messages::NotifyJob)
      assert_equal 2, @bob.notifications.count, "read, it's news again"

      direct = Conversation.direct_between(@alice, @bob)
      send_message(direct, @alice, "psst", notify: true)
      perform_enqueued_jobs(only: Messages::NotifyJob)
      assert_equal "Alice sent you a message", wording_of(@bob.notifications.message_received.where(subject: direct).sole).title
    end
  end

  test "a message unsent before the bell rings says nothing" do
    message = send_message(@chat, @alice, "nothing", notify: true)
    message.unsend!

    perform_enqueued_jobs(only: Messages::NotifyJob)
    assert_equal 0, Notification.count
  end

  test "reading tells the others, and keeps the reader's own count current" do
    message = send_message(@chat, @alice, "seen?")
    @chat.participant_for(@carol).read_up_to!(message)
    @chat.participant_for(@bob).read_up_to!(message)

    alice_page = capture_turbo_stream_broadcasts([ @chat, @alice ]) do
      bob_pages = capture_turbo_stream_broadcasts([ @bob, :notifications ]) do
        Conversations::Broadcaster.read(@chat, @bob)
      end
      assert_equal([ "conversation-row-#{@chat.id}", ".messages-badge" ], bob_pages.map { _1["target"] || _1["targets"] })
    end
    assert_equal([ "conversation-#{@chat.id}-seen" ], alice_page.map { _1["target"] })
    assert_includes alice_page.first.to_html, "Seen by Bob and Carol"
  end

  test "two sends of one message at once save it once, and the later one answers with it" do
    press = { conversation: @chat, sender: @alice, body: "dinner's ready", client_id: SecureRandom.uuid, notify: false }
    first = Messages::Send.call(**press)
    checked = Message.validators_on(:client_id).grep(ActiveRecord::Validations::UniquenessValidator).sole
    second = nil

    # As if the first send hadn't committed when the second one looked and checked.
    swapping(@chat.messages, :find_by, ->(*) { nil }) do
      swapping(checked, :validate_each, ->(*) { nil }) do
        assert_no_difference("Message.count") { second = Messages::Send.call(**press) }
      end
    end

    assert_equal first, second
  end
end
