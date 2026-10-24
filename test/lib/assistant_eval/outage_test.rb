# frozen_string_literal: true

require "test_helper"

# Waiting out a model-server outage mid-run (AssistantEval::Outage).
class AssistantEval::OutageTest < ActiveSupport::TestCase
  test "waits, polling, until the model answers again" do
    checks = 0
    check = ->(**) { (checks += 1) < 3 ? raise(AssistantEval::Preflight::Unavailable, "down") : true }
    slept = []

    waited = swapping(AssistantEval::Preflight, :check!, check) do
      AssistantEval::Outage.wait(limit: 60, poll: 5, sleeper: ->(s) { slept << s })
    end

    assert_equal 3, checks
    assert_equal [ 5, 5, 5 ], slept
    assert_operator waited, :>=, 0
  end

  test "gives up once the limit is spent" do
    checks = 0
    check = ->(**) { checks += 1; raise AssistantEval::Preflight::Unavailable, "down" }

    waited = swapping(AssistantEval::Preflight, :check!, check) do
      AssistantEval::Outage.wait(limit: 0, poll: 5, sleeper: ->(_) { flunk "nothing to wait for" })
    end

    assert_nil waited
    assert_equal 0, checks
  end
end
