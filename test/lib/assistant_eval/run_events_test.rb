# frozen_string_literal: true

require "test_helper"

class AssistantEval::RunEventsTest < ActiveSupport::TestCase
  EVENTS = [
    { type: "run_started", cases: [ { scenario: "04", rep: 1 }, { scenario: "04", rep: 2 } ] },
    { type: "scenario_started", index: 0, scenario: "04", rep: 1 },
    { type: "turn_started", index: 0, turn: "0-1", said: "Cobalamin 250" },
    { type: "reply", turn: "0-1", text: "<think>which tool" },
    { type: "tool_started", seq: 1, turn: "0-1", tool: "record_lab_results" },
    { type: "tool_call", seq: 1, turn: "0-1", tool: "record_lab_results", ok: true, ms: 40 },
    { type: "reply", turn: "0-1", text: "<think>which tool</think>Saved" },
    { type: "turn_finished", index: 0, turn: "0-1", reply: "<think>which tool</think>Saved it.", outcome: "ok" },
    { type: "scenario_finished", index: 0, scenario: "04", rep: 1, status: "passed" },
    { type: "scenario_started", index: 1, scenario: "04", rep: 2 },
    { type: "turn_started", index: 1, turn: "1-1", said: "Cobalamin 250" },
    { type: "tool_started", seq: 2, turn: "1-1", tool: "record_lab_results" }
  ].freeze

  setup do
    @path = Pathname(Dir.mktmpdir).join("run.events.jsonl")
    @path.write(EVENTS.map { |e| JSON.generate(e.merge(t: 1_790_000_000)) }.join("\n") + "\n{\"type\":\"repl") # a line cut mid-write
    @events = AssistantEval::RunEvents.new(@path)
  end

  teardown { FileUtils.remove_entry(@path.dirname) }

  test "a line cut off mid-write is skipped" do
    assert_equal EVENTS.size, @events.size
  end

  test "every planned scenario run has a state" do
    assert_equal(%w[passed running], @events.cases.map { |c| c["state"] })
  end

  test "what the agent is doing now" do
    assert_equal({ "phase" => "tool", "tool" => "record_lab_results" }, @events.now)
  end

  test "the full timeline shows each tool call once, finished, and one reply per turn with its final text" do
    shown = @events.display
    tools = shown.select { |e| e["seq"] }
    assert_equal [ "tool_call", "tool_started" ], tools.map { |e| e["type"] }, "call 1 finished, call 2 still running"
    replies = shown.select { |e| e["type"] == "reply" }
    assert_equal([ "<think>which tool</think>Saved it." ], replies.map { |e| e["text"] })
  end

  test "updates since a poll replace what's on screen and append what's new" do
    steps = @events.updates(5).map { |action, target, _| [ action, target ] }

    assert_equal [ :replace, "eval-tool-1" ], steps[0], "the running card becomes the finished one"
    assert_equal [ :replace, "eval-reply-0-1" ], steps[1], "more of the same reply"
    assert_includes steps, [ :replace, "eval-case-0" ]
    assert_equal [ :append, "eval-timeline" ], steps.last
  end
end
