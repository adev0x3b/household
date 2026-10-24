# frozen_string_literal: true

require "test_helper"

class AssistantEval::OverviewTest < ActiveSupport::TestCase
  Scenario = Struct.new(:name, :tags)

  def run_file(id, model, results, errors: 0)
    rows = results.map { |scenario, passed| { "scenario" => scenario, "passed" => passed, "seconds" => 10 } }
    rows += Array.new(errors) { { "scenario" => "a", "status" => "error", "error" => "the model server was unreachable", "seconds" => 1 } }
    AssistantEval::RunFile.new(id, { "model" => model, "provider" => "ollama", "finished" => true, "results" => rows })
  end

  setup do
    @runs = [
      run_file("3", "qwen", [ [ "a", true ], [ "b", false ] ]),
      run_file("2", "haiku", [ [ "a", true ], [ "b", true ] ]),
      run_file("1", "qwen", [ [ "a", false ], [ "b", false ], [ "gone", false ] ]),
      run_file("0", "qwen", [])
    ]
    @overview = AssistantEval::Overview.new(runs: @runs, scenarios: [ Scenario.new("a", []), Scenario.new("b", []) ])
  end

  test "the latest run is compared with the one before it on the same model" do
    assert_equal "3", @overview.latest.id
    assert_equal "1", @overview.previous.id
    assert_equal [ 0.0, 100.0, 50.0 ], @overview.trend.map { |run| AssistantEval::Overview.percent(run) }, "oldest first, unscored runs left out"
    assert_in_delta(10.0, AssistantEval::Overview.seconds_per_case(@overview.latest))
  end

  test "one entry per model: its latest run, its best rate, how many runs" do
    qwen, haiku = @overview.models

    assert_equal [ "qwen", 2, "3", 0.5 ], [ qwen.name, qwen.runs, qwen.latest.id, qwen.best ]
    assert_equal [ "haiku", 1, 1.0 ], [ haiku.name, haiku.runs, haiku.best ]
  end

  test "the scenarios on file that failed, worst first, with the newest run where each did" do
    b, a = @overview.attention

    assert_equal [ "b", 1, 3, "3" ], [ b.scenario, b.passed, b.scored, b.last_failed.id ]
    assert_equal [ "a", 2, 3, "1" ], [ a.scenario, a.passed, a.scored, a.last_failed.id ]
    assert_not b.flaky, "failed every time in the latest run"
  end

  test "a run with too much unscored is never the headline or a point on the trend, and flaky scenarios are marked" do
    outage = run_file("4", "qwen", [ [ "a", true ] ], errors: 3)
    flaky = run_file("5", "qwen", [ [ "a", true ], [ "a", false ], [ "b", false ] ])
    overview = AssistantEval::Overview.new(runs: [ outage, *@runs ], scenarios: [ Scenario.new("a", []), Scenario.new("b", []) ])

    assert_equal "3", overview.latest.id, "the outage run is skipped"
    assert_not_includes overview.trend.map(&:id), "4"
    marked = AssistantEval::Overview.new(runs: [ flaky, *@runs ], scenarios: [ Scenario.new("a", []), Scenario.new("b", []) ]).attention
    assert_equal({ "a" => true, "b" => false }, marked.to_h { |item| [ item.scenario, item.flaky ] })
  end
end
