# frozen_string_literal: true

require "test_helper"

# What the assistant cost each household (Assistant::Usage), from RubyLLM's
# usage rows and the messages people sent.
class Assistant::UsageTest < ActiveSupport::TestCase
  def step!(chat, input:, output:, cost: nil, at: Time.current)
    RubyLLM::ActiveRecord::Usage.create!(chat: chat, model: "m", provider: "ollama", operation: "chat", status: "succeeded",
                                         input_tokens: input, output_tokens: output, total_cost: cost, created_at: at)
  end

  test "tokens, messages and cost per household, heaviest first; a household that never asked reads as zeros" do
    ours = assistant_chat(profiles(:alice))
    theirs = assistant_chat(profiles(:outsider))
    ours.assistant_messages.create!(role: "user", content: "hi")
    ours.assistant_messages.create!(role: "user", content: "a note", hidden: true)
    theirs.assistant_messages.create!(role: "user", content: "ciao")
    step!(ours, input: 1_000, output: 100)
    step!(ours, input: 2_000, output: 200, cost: 0.0123)
    step!(theirs, input: 5_000, output: 50)
    step!(ours, input: 9_999, output: 1, at: 2.months.ago)

    rows = Assistant::Usage.by_household

    assert_equal [ profiles(:outsider).household, profiles(:alice).household ], rows.map(&:household)
    mine = rows.last
    assert_equal [ 1, 3_000, 300, 3_300 ], [ mine.messages, mine.input_tokens, mine.output_tokens, mine.tokens ], "the hidden note isn't a message; last month doesn't count"
    assert_equal 0.0123.to_d, mine.cost
    assert_predicate mine, :cost?
    assert_not rows.first.cost?
    quiet = Household.create!(name: "Quiet")
    assert_equal([ 0, 0, 0 ], Assistant::Usage.for(quiet).then { |row| [ row.messages, row.tokens, row.cost.to_i ] })
    assert_equal 3_300, profiles(:alice).household.assistant_usage.tokens
  end
end
