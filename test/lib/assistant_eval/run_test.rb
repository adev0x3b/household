# frozen_string_literal: true

require "test_helper"

# A run as `assistant:eval` starts it, with the scenarios played by a stand-in
# (no model): the files the dashboard reads, the summary, and an outage.
class AssistantEval::RunTest < ActiveSupport::TestCase
  Scenario = Struct.new(:name)

  setup do
    @dir = Pathname(Dir.mktmpdir)
    @out = StringIO.new
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "plays every scenario as many times as asked, keeps the results and the events, and sums them up" do
    outcomes = { "logs a dose" => [ true, false ], "books a visit" => [ true, true ] }
    run = run_of(outcomes.keys, runs: 2, play: ->(scenario, rep:, **) { result(scenario.name, passed: outcomes.fetch(scenario.name)[rep - 1]) })

    path = run.call

    data = JSON.parse(path.read)
    assert data["finished"]
    assert_equal [ 4, 4 ], [ data["total"], data["results"].size ]
    assert_equal(%w[passed failed passed passed], data["results"].map { _1["status"] })
    assert_predicate path.sub_ext(".events.jsonl"), :exist?
    assert_match(/logs a dose\s+1\/2/, @out.string)
    assert_match(/TOTAL\s+3\/4 \(75%\)/, @out.string)
  end

  test "an outage is waited out, not scored; past the wait it finishes with what it has" do
    play = ->(scenario, **) { result(scenario.name, error: "connection refused", error_class: "unreachable") }
    run = run_of([ "a", "b", "c", "d" ], runs: 1, play: play, outage: { after: 2, wait: 5.0, poll: 1.0 })

    path = swapping(AssistantEval::Outage, :wait, ->(**) { nil }) { run.call }

    data = JSON.parse(path.read)
    assert data["gave_up"]
    assert_equal 2, data["results"].size, "it stopped at the outage"
    assert_match "UNRELIABLE", @out.string
  end

  test "nothing matching is refused before anything is written" do
    error = assert_raises(AssistantEval::Run::NotStarted) { run_of([], runs: 1, play: ->(*) { flunk }).call }
    assert_match "No scenarios match", error.message
    assert_empty @dir.children
  end

  private

  def run_of(names, runs:, play:, outage: { after: 3, wait: 1800.0, poll: 15.0 })
    AssistantEval::Run.new(scenarios: names.map { Scenario.new(_1) }, runs: runs, out: @out, preflight: false, play: play,
                           results_path: @dir.join("run.json").to_s, outage: outage)
  end

  def result(name, passed: false, error: nil, error_class: nil)
    AssistantEval::Runner::Result.new(scenario: name, passed: passed, failures: passed ? [] : [ "it didn't" ], turns: [], seconds: 1.0,
                                      error: error, error_class: error_class)
  end
end
