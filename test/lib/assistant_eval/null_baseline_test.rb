# frozen_string_literal: true

require "test_helper"

# Every scenario must fail when nothing is said — otherwise it would pass
# for a model that does nothing (AssistantEval::NullBaseline).
class AssistantEval::NullBaselineTest < ActiveSupport::TestCase
  AssistantEval::Scenario.all.each do |scenario|
    test "#{scenario.name} fails when nothing is said" do
      assert_not AssistantEval::NullBaseline.lenient?(scenario),
                 "#{scenario.name}'s checks already hold with nothing saved — make them check what the conversation should change"
    end
  end

  test "a scenario that only checks for nothing is caught" do
    lenient = AssistantEval::Scenario.new(name: "99_lenient", description: "", today: Date.new(2026, 9, 26), seed: [],
                                          messages: [ "Book Moretti for Friday" ], expect: [ { "appointments" => 0 } ])

    assert AssistantEval::NullBaseline.lenient?(lenient)
  end
end
