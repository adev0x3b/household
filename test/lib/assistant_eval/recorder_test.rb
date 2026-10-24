# frozen_string_literal: true

require "test_helper"

class AssistantEval::RecorderTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname(Dir.mktmpdir)
    @recorder = AssistantEval::Recorder.new(@dir.join("run.events.jsonl"))
    @recorder.watch(chat_id: 7)
    @recorder.turn = "0-1"
  end

  teardown do
    @recorder.close
    FileUtils.remove_entry(@dir)
  end

  def events = AssistantEval::RunEvents.new(@dir.join("run.events.jsonl")).all

  def call_tool(chat_id, ok: true)
    ActiveSupport::Notifications.instrument("tool_call.assistant", chat_id: chat_id, tool: "record_lab_results", arguments: { values: [] }) do |payload|
      payload.merge!(ok: ok, error: (ok ? nil : "give values"), result: { ok: ok })
    end
  end

  test "a tool call is recorded when it starts and when it finishes, for the watched chat only" do
    call_tool(7)
    call_tool(8)
    call_tool(7, ok: false)

    assert_equal(%w[tool_started tool_call tool_started tool_call], events.map { |e| e["type"] })
    started, finished = events.first(2)
    assert_equal [ 1, 1, "0-1" ], [ started["seq"], finished["seq"], finished["turn"] ]
    assert_equal({ "values" => [] }, finished["arguments"])
    assert_equal [ false, "give values" ], events.last.values_at("ok", "error")
  end

  test "reply text is kept as snapshots, at most one a second" do
    3.times { |i| ActiveSupport::Notifications.instrument("reply_text.assistant", chat_id: 7, text: "part #{i}") }
    ActiveSupport::Notifications.instrument("reply_text.assistant", chat_id: 8, text: "other chat")

    replies = events.select { |e| e["type"] == "reply" }
    assert_equal([ "part 0" ], replies.map { |e| e["text"] })
  end

  test "times are real even while a scenario travels in time" do
    travel_to(Time.utc(2026, 1, 1)) { @recorder.event("turn_started", turn: "0-1") }

    assert_in_delta Process.clock_gettime(Process::CLOCK_REALTIME), events.last["t"], 5
  end
end
