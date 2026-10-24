# frozen_string_literal: true

require "test_helper"
require "rake"

# The dashboard reads what `assistant:eval` writes while it runs.
class AssistantEvalRakeTest < ActiveSupport::TestCase
  # First run passes; every later one hits an unreachable model server.
  class FakeRunner
    @calls = 0
    class << self
      attr_accessor :calls
    end

    def initialize(scenario) = @scenario = scenario

    def call
      self.class.calls += 1
      turn = AssistantEval::Runner::Turn.new(said: "hi", tools: [], reply: "ok", seconds: 0.1)
      error = ("the model server was unreachable" if self.class.calls > 1)
      AssistantEval::Runner::Result.new(scenario: @scenario.name, passed: error.nil?, failures: [], turns: [ turn ], seconds: 0.1,
                                        error: error, error_class: error && "unreachable")
    end
  end

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("assistant:eval")
    @dir = Pathname(Dir.mktmpdir)
    FakeRunner.calls = 0
  end

  teardown { FileUtils.remove_entry(@dir) }

  def run_eval(env, runs: "2")
    with_env(env) do
      capture_io do
        Rake::Task["assistant:eval"].reenable
        Rake::Task["assistant:eval"].invoke(runs)
      end
    end
  end

  test "a draft file's results are written with finished: true, errors apart from failures" do
    results = @dir.join("run.json")
    out, = swapping(AssistantEval::Runner, :new, ->(scenario, **) { FakeRunner.new(scenario) }) do
      run_eval({ "SCENARIO_FILE" => Rails.root.join("eval/assistant/scenarios/04_lab_report_alone.yml").to_s,
                 "EVAL_RESULTS" => results.to_s, "EVAL_SKIP_PREFLIGHT" => "1" })
    end

    data = JSON.parse(results.read)
    assert data["finished"]
    assert_equal 2, data["total"]
    assert_equal(%w[passed error], data["results"].map { |r| r["status"] })
    assert_equal "04_lab_report_alone", data["draft"]
    assert_match %r{TOTAL\s+1/1 \(100%\) · 1 not scored}, out, "the error isn't counted as a failure"

    events = AssistantEval::RunEvents.new(@dir.join("run.events.jsonl"))
    assert_equal %w[run_started run_finished], events.all.map { |e| e["type"] }, "the fake runner records nothing itself"
    assert_equal([ 1, 2 ], events.cases.map { |c| c["rep"] })
  end

  test "unreachable results in a row make the run wait for the model, and give up when it stays away" do
    results = @dir.join("run.json")
    unreachable = ->(**) { raise AssistantEval::Preflight::Unavailable, "still down" }
    out, = swapping(AssistantEval::Runner, :new, ->(scenario, **) { FakeRunner.new(scenario) }) do
      swapping(AssistantEval::Preflight, :check!, unreachable) do
        run_eval({ "SCENARIO_FILE" => Rails.root.join("eval/assistant/scenarios/04_lab_report_alone.yml").to_s, "EVAL_RESULTS" => results.to_s,
                   "EVAL_SKIP_PREFLIGHT" => "1", "EVAL_OUTAGE_AFTER" => "2", "EVAL_OUTAGE_WAIT" => "0" }, runs: "6")
      end
    end

    data = JSON.parse(results.read)
    assert data["finished"]
    assert data["gave_up"]
    assert_equal %w[passed error error], data["results"].map { |r| r["status"] }, "stopped after the outage, not after 6"
    assert_match(/stayed unreachable.*finishing with what was scored/, out)
    assert_match %r{TOTAL\s+1/1 \(100%\) · 2 not scored \(errors\) · UNRELIABLE: 2 of 3 not scored}, out
    events = AssistantEval::RunEvents.new(@dir.join("run.events.jsonl")).all.map { |e| e["type"] }
    assert_equal %w[run_started outage_started outage_ended run_finished], events
  end

  test "an unreachable model stops the run before it starts" do
    unreachable = ->(**) { raise AssistantEval::Preflight::Unavailable, "the Ollama server isn't answering" }
    error = assert_raises(SystemExit) do
      swapping(AssistantEval::Preflight, :check!, unreachable) do
        run_eval({ "SCENARIOS" => "04_lab_report_alone", "EVAL_RESULTS" => @dir.join("run.json").to_s })
      end
    end

    assert_not error.success?
    assert_not @dir.join("run.json").exist?, "nothing was written"
  end
end
