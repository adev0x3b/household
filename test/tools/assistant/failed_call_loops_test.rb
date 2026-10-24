# frozen_string_literal: true

require "test_helper"

# A model that repeats a failing call, or keeps failing the same way, is
# stopped and told to explain instead of looping until the step cap.
class Assistant::FailedCallLoopsTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 9, 24, 12)
    @profile = AssistantEval::Sandbox.profile!
    @chat = assistant_chat(@profile)
    AssistantEval::Seeds.moretti_oct2(@profile)
    @tool = Assistant::ShareTool.new(chat: @chat)
  end

  teardown { travel_back }

  test "the exact same failing call isn't run again" do
    first = @tool.call(type: "appointment", ref: "Moretti", with: "Giulia")
    runs = 0
    second = swapping(@tool, :execute, ->(**) { runs += 1 }) { @tool.call(type: "appointment", ref: "Moretti", with: "Giulia") }

    assert_match(/nobody called Giulia/, first[:error])
    assert_not first[:stop]
    assert second[:stop]
    assert_match(/\AStop: share already failed this way this turn \(.*nobody called Giulia/, second[:error])
    assert_equal 0, runs
  end

  test "failing the same way with other arguments stops the second time" do
    @tool.call(type: "appointment", ref: "Moretti", with: "Giulia")
    second = @tool.call(type: "appointment", ref: "Checkup", with: "Giulia")

    assert second[:stop], second.inspect
    assert_match(/nobody called Giulia/, second[:error])
  end

  test "a different failure isn't a loop, and a new turn starts clean" do
    @tool.call(type: "appointment", ref: "Moretti", with: "Giulia")
    other = @tool.call(type: "appointment", ref: "Moretti", with: "Luca")
    assert_not other[:stop], other.inspect

    fresh = Assistant::ShareTool.new(chat: @chat).call(type: "appointment", ref: "Moretti", with: "Giulia")
    assert_not fresh[:stop]
  end

  test "a call that doesn't fit the schema is told how to reshape it, never to ask the user" do
    tool = Assistant::RecordGroceriesTool.new(chat: @chat)
    first = tool.call(items: [ { ingredient: "flour" } ], colour: "white")
    second = tool.call(items: [ { ingredient: "flour" } ], colour: "white")

    assert_match(/Invalid tool arguments.*unknown keyword.*don't ask them again/m, first[:error])
    assert_not first[:stop]
    assert second[:stop]
    assert_match(/don't fit its schema/, second[:error])
    assert_no_match(/what you need from them/, second[:error])
  end
end
