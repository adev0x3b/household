# frozen_string_literal: true

require "test_helper"

# The checks a scenario can name, and how a scenario's list of them is run.
class AssistantEval::ChecksTest < ActiveSupport::TestCase
  setup do
    @profile = AssistantEval::Sandbox.profile!
  end

  test "every check has a name of its own, words for its argument and an example" do
    keys = AssistantEval::Checks.all.map(&:key)

    assert_equal keys.uniq, keys
    AssistantEval::Checks.all.each do |check|
      assert_predicate check.argument, :present?, check.key
      refute_nil check.example, check.key
      assert_equal check, AssistantEval::Checks.named(check.key)
    end
  end

  test "every scenario names only checks there are" do
    unknown = AssistantEval::Scenario.all.flat_map { |scenario| scenario.expect.flat_map(&:keys).map { "#{scenario.name}: #{_1}" unless AssistantEval::Checks.named(_1) } }

    assert_empty unknown.compact
  end

  test "a check there isn't, or one that breaks on its argument, fails the scenario with the reason" do
    failures = AssistantEval::Expectations.new(@profile).failures([ { "lab_count" => 1 }, { "lab_date" => "not a date" } ])

    assert_equal [ "lab_count: no such check", "lab_date: Date::Error: invalid date" ], failures
  end

  test "the checks every scenario gets run with turns, unless the scenario names them" do
    turn = AssistantEval::Runner::Turn.new(said: "hi", tools: [], reply: "Saved it with update_record.", seconds: 1.0, applied: 0, asked: false)

    assert_equal %w[honest_replies plain_replies], AssistantEval::Checks.all.select(&:on_by_default?).map(&:key)
    assert_equal 2, AssistantEval::Expectations.new(@profile, turns: [ turn ]).failures([]).size
    switched_off = AssistantEval::Expectations.new(@profile, turns: [ turn ]).failures([ { "plain_replies" => false } ]).map { |reason| reason[/\A\w+/] }
    assert_equal [ "honest_replies" ], switched_off
    assert_empty AssistantEval::Expectations.new(@profile).failures([]), "without turns there is no conversation to judge"
  end

  test "numbers compare as decimals, with a comma for the point, and anything else as words" do
    lab_result!(profile: @profile, date: Date.current, values: { "Hemoglobin" => "13,5", "HIV" => "Negative" })
    check = ->(values) { AssistantEval::Expectations.new(@profile).failures([ { "lab_values" => values } ]) }

    assert_empty check.({ "Hemoglobin" => 13.5, "HIV" => "negative" })
    assert_equal 1, check.({ "HIV" => "positive" }).size, "two words that aren't numbers are not the same number"
    assert_equal 1, check.({ "Hemoglobin" => 13.6 }).size
  end

  test "a kind of series is named as a scenario writes it" do
    records = AssistantEval::Checks::Records.new(@profile)

    assert_equal 0, records.days("lab_test_result").count
    assert_raises(KeyError) { records.series("spaceship") }
  end
end
