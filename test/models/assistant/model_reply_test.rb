# frozen_string_literal: true

require "test_helper"

class Assistant::ModelReplyTest < ActiveSupport::TestCase
  test "a reply that thinks first answers with what follows its thinking" do
    reply = Assistant::ModelReply.new("<think>Two tasks match.</think>\n\nWhich one did you mean?")

    assert_equal "Which one did you mean?", reply.answer
    assert_equal "Two tasks match.", reply.thinking
  end

  test "a reply whose opening tag was left to the chat template starts mid-thought" do
    reply = Assistant::ModelReply.new("The user wants Tuesday.</think>Saved for Tuesday.")

    assert_equal "Saved for Tuesday.", reply.answer
    assert_equal "The user wants Tuesday.", reply.thinking
  end

  test "a reply cut off while thinking has no answer" do
    reply = Assistant::ModelReply.new("<think>First I should look up the")

    assert_equal "", reply.answer
    assert_equal "First I should look up the", reply.thinking
  end

  test "every block of thinking is kept, and none of it is answered" do
    reply = Assistant::ModelReply.new("<think>One.</think>Looking.<think>Two.</think> Done.")

    assert_equal "Looking. Done.", reply.answer
    assert_equal "One.\n\nTwo.", reply.thinking
  end

  test "a reply without thinking is all answer" do
    reply = Assistant::ModelReply.new("  Saved your appointment.\n")

    assert_equal "Saved your appointment.", reply.answer
    assert_equal "", reply.thinking
  end

  test "no text is an empty answer" do
    assert_equal "", Assistant::ModelReply.new(nil).answer
  end
end
