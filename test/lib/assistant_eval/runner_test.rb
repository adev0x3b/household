# frozen_string_literal: true

require "test_helper"

# How a scenario run is scored: the model's failures count, the plumbing's
# errors (unreachable server, a crash) don't. No model is called — the reply
# job is swapped for one that only reports how the turn ended.
class AssistantEval::RunnerTest < ActiveSupport::TestCase
  def scenario(messages: [ "Cobalamin 250, test was today" ])
    AssistantEval::Scenario.new(name: "t", description: "", today: Date.new(2026, 9, 26), seed: [], messages: messages,
                                expect: [ { "lab_results" => 1 } ])
  end

  def replying(outcome, served: [ Assistant.model ], pause: 0, &)
    reply = lambda do |chat, _claimed_at|
      sleep(pause)
      chat.release_reply!
      ActiveSupport::Notifications.instrument("turn.assistant", chat_id: chat.id, outcome: outcome, input_tokens: 900, output_tokens: 40,
                                                                served: served)
    end
    swapping(Assistant::ReplyJob, :perform_now, reply, &)
  end

  test "a turn past the time limit is an error, and the run moves on" do
    result = swapping(AssistantEval::Runner, :turn_timeout, -> { 0.05 }) do
      replying("ok", pause: 1) { AssistantEval::Runner.new(scenario).call }
    end

    assert_equal [ "error", "timeout" ], [ result.status, result.error_class ]
    assert_match "longer than 0s", result.error
  end

  test "an answer from another model than the one asked for is an error" do
    result = replying("ok", served: [ "llama3.1:latest" ]) { AssistantEval::Runner.new(scenario).call }
    assert_equal [ "error", "wrong_model" ], [ result.status, result.error_class ]

    tagged = replying("ok", served: [ "#{Assistant.model}:latest" ]) { AssistantEval::Runner.new(scenario).call }
    assert_equal "failed", tagged.status, "an Ollama :latest tag is the same model"
  end

  test "an unreachable model server is an error, not a failure" do
    result = replying("unreachable") { AssistantEval::Runner.new(scenario).call }

    assert_equal "error", result.status
    assert_equal "unreachable", result.error_class
    assert_empty result.failures, "the expectations aren't scored"
  end

  test "a model that answered but saved nothing fails, with its tokens recorded" do
    result = replying("ok") { AssistantEval::Runner.new(scenario).call }

    assert_equal "failed", result.status
    assert_equal [ "lab_results: expected 1, got 0" ], result.failures
    assert_equal [ 900, 40, "ok" ], result.turns.first.to_h.values_at(:input_tokens, :output_tokens, :outcome)
    assert_equal "failed", result.to_h[:status]
  end

  test "a !photo turn plays like an attached photo: the caption with the photos' text appended, as the OCR job writes it" do
    seen = nil
    reply = lambda do |chat, _claimed_at|
      seen = chat.assistant_messages.order(:created_at, :id).last(2).map { |m| [ m.role, m.content ] }
      chat.release_reply!
      ActiveSupport::Notifications.instrument("turn.assistant", chat_id: chat.id, outcome: "ok", served: [ Assistant.model ])
    end
    swapping(Assistant::ReplyJob, :perform_now, reply) do
      AssistantEval::Runner.new(scenario(messages: [ "!photo\nGlucosio 92 mg/dL 70 - 99\n---\nCreatinina 0,9 mg/dL 0,5 - 1,1" ])).call
    end

    assert_equal 1, seen.size, "one user message, no note"
    role, content = seen.last
    assert_equal "user", role
    assert_equal Assistant::LabReportOcrJob.attach_text(I18n.t("assistant.defaults.lab_photo_caption"), [ "Glucosio 92 mg/dL 70 - 99", "Creatinina 0,9 mg/dL 0,5 - 1,1" ]), content
    assert_match(/Page 2 of 2:.*set_reference_ranges/m, content)
  end

  test "the live tracker hears the scenario and each turn, in order" do
    dir = Pathname(Dir.mktmpdir)
    recorder = AssistantEval::Recorder.new(dir.join("run.events.jsonl"))
    replying("ok") { AssistantEval::Runner.new(scenario, recorder: recorder, index: 3, rep: 2).call }
    recorder.close

    events = AssistantEval::RunEvents.new(dir.join("run.events.jsonl")).all
    assert_equal(%w[scenario_started turn_started turn_finished scenario_finished], events.map { |e| e["type"] })
    assert_equal [ "3-1", "2026-09-26" ], events[1].values_at("turn", "date")
    assert_equal [ 3, 2, "failed" ], events.last.values_at("index", "rep", "status")
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  test "a crash in the harness is an error" do
    result = replying("ok") { AssistantEval::Runner.new(scenario(messages: [ "!explode" ])).call }

    assert_equal "error", result.status
    assert_equal "harness", result.error_class
  end

  test "the chat speaks the scenario's language" do
    seen = nil
    reply = lambda do |chat, _claimed_at|
      seen = chat.locale
      chat.release_reply!
      ActiveSupport::Notifications.instrument("turn.assistant", chat_id: chat.id, outcome: "ok", served: [ Assistant.model ])
    end
    italian = AssistantEval::Scenario.new(name: "t", description: "", today: Date.new(2026, 9, 26), seed: [], messages: [ "Ciao" ],
                                          expect: [ { "lab_results" => 1 } ], locale: "it")
    swapping(Assistant::ReplyJob, :perform_now, reply) { AssistantEval::Runner.new(italian).call }

    assert_equal "it", seen
  end

  test "each turn knows what it saved, so a reply's claims can be checked against it" do
    reply = lambda do |chat, _claimed_at|
      Assistant::ChangeSet.create!(chat: chat, profile: chat.profile, status: :applied, applied_at: Time.current, operations: [], undo_log: [])
      chat.assistant_messages.create!(role: "assistant", content: "Saved your lab report.")
      chat.release_reply!
      ActiveSupport::Notifications.instrument("turn.assistant", chat_id: chat.id, outcome: "ok", served: [ Assistant.model ])
    end
    result = swapping(Assistant::ReplyJob, :perform_now, reply) do
      AssistantEval::Runner.new(scenario(messages: [ "Cobalamin 250, test was today", "!undo" ])).call
    end

    assert_equal [ 1, 0 ], result.turns.map(&:applied)
    assert_equal "undid change set", result.turns.last.reply[0, 16]
    assert_not result.failures.any? { |failure| failure.start_with?("honest_replies") }, result.failures.inspect
  end
end
