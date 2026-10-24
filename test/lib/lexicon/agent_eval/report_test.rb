# frozen_string_literal: true

require "test_helper"

# The assistant tests read back from an import's report: what each
# scenario's name says it tested, and nothing at all before the step ran.
class Lexicon::AgentEval::ReportTest < ActiveSupport::TestCase
  def import_with(agent) = LexiconImport.new(language: "it", report: { "agent" => agent })

  test "a scenario's name says the language, the concept and the kind of test" do
    results = [ { "scenario" => "it_test_strip_dose_native_supplies", "status" => "passed" },
                { "scenario" => "en_needle_control_purchase", "status" => "failed", "error" => "the model timed out" } ]
    report = Lexicon::AgentEval::Report.of(import_with("status" => "failed", "passed" => 1, "scored" => 2, "results" => results))

    strip, control = report.results
    assert_equal [ "it", "test strip", "dose_native_supplies", false ], [ strip.code, strip.concept, strip.kind.name, strip.control? ]
    assert_equal [ "en", "needle", "control_purchase", true ], [ control.code, control.concept, control.kind.name, control.control? ]
    assert_equal [ control ], report.failing
    assert_equal "the model timed out", control.reason
    assert_not report.passed?
  end

  test "a re-run in progress is running and says so; before any run there is nothing" do
    assert_predicate Lexicon::AgentEval::Report.of(import_with("status" => "running", "rerun" => true)), :running?
    assert Lexicon::AgentEval::Report.of(import_with("status" => "running", "rerun" => true)).rerun

    assert_not Lexicon::AgentEval::Report.of(LexiconImport.new(report: {})).any?
    assert_not Lexicon::AgentEval::Report.of(nil).any?
  end
end
