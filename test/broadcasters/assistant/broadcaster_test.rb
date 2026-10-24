# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# A reply lands where the chat page draws its thread, and is then written
# over and removed by the id the reply gives itself.
class Assistant::BroadcasterTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @chat = assistant_chat(profiles(:alice))
  end

  test "a reply is added to the page's thread, then written over and removed where it is drawn" do
    streams = capture_turbo_stream_broadcasts(@chat) do
      Assistant::Broadcaster.start(@chat)
      Assistant::Broadcaster.reply_text(@chat, "Half done")
      Assistant::Broadcaster.finish(@chat, nil)
    end

    pushed = streams.map { [ _1["action"], _1["target"] ] }
    assert_equal [ %w[append assistant-thread], %w[replace assistant-reply], %w[remove assistant-reply], %w[replace assistant-composer] ], pushed
    assert_equal Views::Assistant::Chats::Show::THREAD_ID, streams.first["target"]
    assert streams.first.at_css("template ##{Views::Assistant::Chats::Reply::ID}"), "the reply carries the id it is written over by"
  end

  test "a reply that failed takes the reply's place with the notice the page draws for it" do
    failure = @chat.reply_failures.create!(reason: :no_answer)
    streams = capture_turbo_stream_broadcasts(@chat) { Assistant::Broadcaster.failure(@chat, failure) }

    pushed = streams.map { [ _1["action"], _1["target"] ] }
    assert_equal [ %w[remove assistant-reply], %w[append assistant-thread], %w[replace assistant-composer] ], pushed
    assert_equal I18n.t("assistant.errors.no_answer"), streams.second.at_css("template .assistant-notice--error").text.strip
  end
end
