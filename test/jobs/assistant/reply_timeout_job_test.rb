# frozen_string_literal: true

require "test_helper"

class Assistant::ReplyTimeoutJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  setup do
    @chat = assistant_chat(profiles(:alice), locale: :it)
    @chat.claim_reply!
    @claimed_at = @chat.replying_since
  end

  test "a reply that never came frees the chat, says so in the thread, and tells whoever runs the app" do
    streams = nil
    report = assert_error_reported(Assistant::ReplyTimeoutJob::Stalled) do
      streams = capture_turbo_stream_broadcasts(@chat) { Assistant::ReplyTimeoutJob.perform_now(@chat, @claimed_at) }
    end

    assert_not @chat.reload.replying?
    assert_equal "stalled", @chat.reply_failures.sole.reason
    assert_includes streams.map(&:text).join(" "), I18n.t("assistant.errors.stalled", locale: :it), "in the chat's language"
    assert_match "assistant", report.error.message
  end

  test "a reply that ended in time leaves nothing to do" do
    @chat.release_reply!(@claimed_at)

    assert_no_error_reported { Assistant::ReplyTimeoutJob.perform_now(@chat, @claimed_at) }
    assert_empty @chat.reply_failures
  end

  test "a newer message's reply is left to run" do
    @chat.release_reply!(@claimed_at)
    travel 1.second
    @chat.claim_reply!

    assert_no_error_reported { Assistant::ReplyTimeoutJob.perform_now(@chat, @claimed_at) }
    assert_predicate @chat.reload, :replying?
  end

  test "a chat deleted meanwhile is nothing to do" do
    Assistant::ReplyTimeoutJob.perform_later(@chat, @claimed_at)
    @chat.destroy!

    assert_nothing_raised { perform_enqueued_jobs(only: Assistant::ReplyTimeoutJob) }
  end
end
