# frozen_string_literal: true

require "test_helper"

class Assistant::Chats::DestroyTest < ActiveSupport::TestCase
  include ActionDispatch::TestProcess::FixtureFile

  setup do
    @alice = profiles(:alice)
  end

  test "a conversation goes with everything in it, and the next one stays" do
    chat, photo = conversation(@alice, turns: 2)
    kept, _ = conversation(@alice, turns: 1)
    before = rows_of(kept)

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { Assistant::Chats::Destroy.call(chat) }

    assert_equal [ 0, 0, 0, 0, 0, 0 ], rows_of(chat)
    assert_not Assistant::Chat.exists?(chat.id)
    assert_not ActiveStorage::Blob.exists?(photo.id), "a photo sent to it goes"
    assert_equal before, rows_of(kept)
  end

  test "a deletion rolled back leaves the photos where they were" do
    chat, photo = conversation(@alice, turns: 1)

    ActiveRecord::Base.transaction(requires_new: true) do
      Assistant::Chats::Destroy.call(chat)
      raise ActiveRecord::Rollback
    end

    assert_no_enqueued_jobs only: ActiveStorage::PurgeJob
    assert ActiveStorage::Blob.exists?(photo.id)
  end

  test "a long conversation is deleted in as many statements as a short one" do
    short, _ = conversation(@alice, turns: 1)
    long, _ = conversation(@alice, turns: 6)

    statements = [ short, long ].map { |chat| count_queries { Assistant::Chats::Destroy.call(chat) } }

    assert_equal statements.first, statements.last
  end

  private

  # A conversation of `turns` questions, each answered after a tool call,
  # with a photo in the first question, one change set and one reply that
  # failed; the photo's blob.
  def conversation(profile, turns:)
    chat = assistant_chat(profile)
    photo = nil
    turns.times do |turn|
      question = chat.assistant_messages.create!(role: "user", content: "question #{turn}")
      photo ||= question.attachments.attach(picture_upload).then { question.attachments.sole.blob }
      call = chat.assistant_messages.create!(role: "assistant", content: "")
      tool_call = call.ruby_llm_tool_calls.create!(tool_call_id: "call-#{chat.id}-#{turn}", name: "search_records", arguments: {})
      chat.assistant_messages.create!(role: "tool", content: "found", ruby_llm_parent_tool_call: tool_call)
      answer = chat.assistant_messages.create!(role: "assistant", content: "answer #{turn}")
      chat.ruby_llm_usages.create!(message: answer, model: "qwen3", provider: "ollama", operation: "chat", status: "succeeded",
                                   input_tokens: 10, output_tokens: 2)
    end
    Assistant::ChangeSet.create!(chat: chat, profile: profile, status: :applied, applied_at: Time.current, operations: [], undo_log: [])
    chat.reply_failures.create!(reason: :unreachable)
    [ chat, photo ]
  end

  def rows_of(chat)
    messages = chat.assistant_messages.ids
    [ messages.size,
      RubyLLM::ActiveRecord::ToolCall.where(message_type: "Assistant::Message", message_id: messages).count,
      RubyLLM::ActiveRecord::Usage.where(chat: chat).count,
      Assistant::ChangeSet.where(chat: chat).count,
      Assistant::ReplyFailure.where(chat: chat).count,
      ActiveStorage::Attachment.where(record_type: "Assistant::Message", record_id: messages).count ]
  end
end
