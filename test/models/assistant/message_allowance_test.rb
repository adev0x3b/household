# frozen_string_literal: true

require "test_helper"

# A household's messages to the assistant for the day, counted from what its
# members sent since midnight.
class Assistant::MessageAllowanceTest < ActiveSupport::TestCase
  test "unlimited unless the installation sets a number" do
    allowance = Assistant::MessageAllowance.new(households(:example))

    assert_nil allowance.left
    assert_predicate allowance, :any_left?
  end

  test "the household's members share one count; another household's, yesterday's and the replies don't count" do
    with_env("ASSISTANT_MESSAGES_PER_DAY" => "3") do
      ours = assistant_chat(profiles(:alice))
      2.times { assistant_chat(profiles(:bob)).assistant_messages.create!(role: "user", content: "hi") }
      ours.assistant_messages.create!(role: "user", content: "yesterday's", created_at: 1.day.ago)
      ours.assistant_messages.create!(role: "assistant", content: "an answer")
      assistant_chat(profiles(:outsider)).assistant_messages.create!(role: "user", content: "theirs")

      allowance = Assistant::MessageAllowance.new(households(:example))
      assert_equal 1, allowance.left
      assert_predicate allowance, :any_left?

      ours.assistant_messages.create!(role: "user", content: "the third")
      assert_equal 0, allowance.left
      assert_not allowance.any_left?
    end
  end
end
