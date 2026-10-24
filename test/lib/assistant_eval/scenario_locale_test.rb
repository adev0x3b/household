# frozen_string_literal: true

require "test_helper"

# A scenario's `locale`: the language its chat is in.
class AssistantEval::ScenarioLocaleTest < ActiveSupport::TestCase
  test "read from the file, English when unsaid, written back only when it isn't" do
    assert_equal "it", AssistantEval::Scenario.find("29_italian_grocery_purchase").locale
    assert_equal "en", AssistantEval::Scenario.find("21_linguine_purchase").locale

    italian = AssistantEval::Scenario.find("29_italian_grocery_purchase")
    assert_match(/^locale: it$/, italian.to_yaml)
    assert_no_match(/^locale:/, AssistantEval::Scenario.find("21_linguine_purchase").to_yaml)
  end

  test "the draft carries it through the form and back into a scenario" do
    draft = AssistantEval::ScenarioDraft.from_scenario(AssistantEval::Scenario.find("29_italian_grocery_purchase"))

    assert_equal "it", draft.locale
    assert_equal "it", draft.to_scenario.locale
    assert_equal "en", AssistantEval::ScenarioDraft.new(today: "2026-10-01").to_scenario.locale
  end
end
