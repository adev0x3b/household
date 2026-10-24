# frozen_string_literal: true

require "test_helper"

# Trimming the history to the model's window (Assistant::Compaction): oldest
# turns first, tool exchanges folded, then whole turns dropped into one note.
class Assistant::CompactionTest < ActiveSupport::TestCase
  def msg(role, content, tool_calls: nil, tool_call_id: nil)
    RubyLLM::Message.new(role: role, content: content, tool_calls: tool_calls, tool_call_id: tool_call_id)
  end

  # One turn: the user's words, a tool call with a long result, the reply.
  def turn(n, result: { ok: true, data: { status: "saved" } })
    call = RubyLLM::ToolCall.new(id: "call-#{n}", name: "record_groceries", arguments: { "items" => [ { "ingredient" => "flour #{n}" } ] })
    [ msg(:user, "I bought flour number #{n}"),
      msg(:assistant, "", tool_calls: { call.id => call }),
      msg(:tool, (result.to_json + (" " * 1500)), tool_call_id: call.id),
      msg(:assistant, "Saved flour #{n}.") ]
  end

  def system = [ msg(:system, "You are the bookkeeper. " * 20) ]

  test "the overhead is learned from the previous reply's token count, else estimated from the prompt and the schemas" do
    chat = assistant_chat(AssistantEval::Sandbox.profile!)
    assert_operator Assistant::Compaction.fixed_overhead(chat), :>, 4_000, "the instructions and twenty schemas alone are thousands of tokens"

    reply = chat.assistant_messages.create!(role: "assistant", content: "Saved flour 1.")
    RubyLLM::ActiveRecord::Usage.create!(chat: chat, message: reply, model: "m", provider: "ollama", operation: "chat", status: "succeeded",
                                         input_tokens: 8_000, output_tokens: 50)
    messages = turn(1) + turn(2) + system
    compaction = Assistant::Compaction.new(messages, chat: chat, context_tokens: 12_288)
    history_before_reply = Assistant::Compaction.estimate(turn(1)[0..2])

    assert_equal 8_000 - history_before_reply, compaction.overhead
  end

  test "without a chat, or before a reply was counted, the overhead is estimated" do
    chat = assistant_chat(AssistantEval::Sandbox.profile!)
    assert_operator Assistant::Compaction.fixed_overhead(nil), :<, Assistant::Compaction.fixed_overhead(chat), "no tools or context without a chat"
    assert_equal Assistant::Compaction.fixed_overhead(nil), Assistant::Compaction.new([], chat: nil, context_tokens: 1).overhead

    assert_equal Assistant::Compaction.fixed_overhead(chat), Assistant::Compaction.new([], chat: chat, context_tokens: 1).overhead, "no reply yet"

    reply = chat.assistant_messages.create!(role: "assistant", content: "Saved.")
    assert_equal Assistant::Compaction.fixed_overhead(chat), Assistant::Compaction.new([], chat: chat, context_tokens: 1).overhead, "a reply nobody counted"

    RubyLLM::ActiveRecord::Usage.create!(chat: chat, message: reply, model: "m", provider: "ollama", operation: "chat", status: "succeeded",
                                         input_tokens: 8_000, output_tokens: 50)
    assert_equal Assistant::Compaction.fixed_overhead(chat), Assistant::Compaction.new(turn(1), chat: chat, context_tokens: 1).overhead,
                 "a counted reply that isn't among the messages sent says nothing about them"
  end

  test "a compaction is reported with its chat" do
    chat = assistant_chat(AssistantEval::Sandbox.profile!)
    reported = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { reported << payload }, "compaction.assistant") do
      Assistant::Compaction.call((1..4).flat_map { turn(_1) } + system, chat: chat, context_tokens: 900, overhead: 0)
    end
    assert_equal chat.id, reported.sole[:chat_id]
    assert_operator reported.sole[:after], :<, reported.sole[:before]
  end

  test "a turn without a tool call, or without a reply, keeps what it has when it is folded or dropped" do
    quiet = [ msg(:user, "just thinking aloud " * 60), msg(:assistant, "") ]
    messages = quiet + quiet + turn(3) + turn(4) + system
    assert Assistant::Compaction.call(messages, context_tokens: 400, overhead: 0)
    assert_match "just thinking aloud", messages.first.content.to_s, "the dropped turns' words are in the note"
    assert_no_match(/\(used/, messages.first.content.to_s.lines.first(3).join, "no tool line for a turn that used none")
  end

  test "nothing happens under the budget, without a known window, or when only the last turns are left" do
    messages = turn(1) + system
    assert_nil Assistant::Compaction.call(messages.dup, context_tokens: 100_000, overhead: 0)
    assert_nil Assistant::Compaction.call(messages.dup, context_tokens: nil, overhead: 0)
    two = turn(1) + turn(2) + system
    assert_nil Assistant::Compaction.call(two, context_tokens: 100, overhead: 0), "two turns are kept whole whatever the budget"
    assert_equal 8 + 1, two.size
  end

  test "the oldest turns' tool exchanges are folded into one line; the last two turns stay whole" do
    messages = (1..4).flat_map { |n| turn(n) } + system
    before = Assistant::Compaction.estimate(messages)

    result = Assistant::Compaction.call(messages, context_tokens: ((before - 700) / 0.75).to_i, overhead: 0)

    assert_equal 2, result.folded
    assert_equal 0, result.dropped
    assert_operator result.after, :<=, before - 700, result.inspect
    texts = messages.map { |m| [ m.role, Assistant::Compaction.text(m)[0, 40] ] }
    assert_equal [ :user, "I bought flour number 1" ], texts[0]
    assert_equal [ :assistant, "(used record_groceries: saved)" ], texts[1]
    assert_equal [ :assistant, "Saved flour 1." ], texts[2]
    assert_equal :tool, messages[3 + 3 + 2].role, "turn 3 keeps its tool result"
    assert_equal :system, messages.last.role
    assert_equal(1, messages.count { |m| m.role == :tool && m.tool_call_id == "call-3" })
    assert_equal(1, messages.count { |m| m.role == :tool && m.tool_call_id == "call-4" })
  end

  test "when folding isn't enough, whole turns are dropped into one note the model reads as the app's" do
    messages = (1..5).flat_map { |n| turn(n) } + system

    result = Assistant::Compaction.call(messages, context_tokens: 1_000, overhead: 0)

    assert_operator result.dropped, :>=, 1, result.inspect
    note = messages.first
    assert_equal :user, note.role
    assert_match(/\A\[Note from the app, not from the user\] Earlier in this conversation/, note.content)
    assert_match(/- user: I bought flour number 1/, note.content)
    assert_match(/- assistant: \(used record_groceries: saved\)/, note.content)
    assert_includes messages.map { |m| Assistant::Compaction.text(m) }, "I bought flour number 5"
    assert_equal :system, messages.last.role
  end

  test "a failed call reads as failed, and the note is what the user said, not the app's notes" do
    note = msg(:user, Assistant::Chat.note_text("The user pressed Apply."))
    messages = turn(1, result: { ok: false, error: "no" }) + [ note ] + turn(2) + turn(3) + system

    Assistant::Compaction.call(messages, context_tokens: 1_000, overhead: 0)

    assert_match(/record_groceries: failed/, messages.first.content)
    assert_no_match(/pressed Apply/, messages.first.content)
  end
end
