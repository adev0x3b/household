# frozen_string_literal: true

require "test_helper"

# Conversations::Readers: who the line under the newest message names, for
# each person looking.
class Conversations::ReadersTest < ActiveSupport::TestCase
  setup do
    @alice, @bob, @carol = profiles(:alice), profiles(:bob), profiles(:carol)
    @chat = Conversation.household_conversation(households(:example))
  end

  def readers = Conversations::Readers.new(@chat.reload)

  test "nobody, before anything is said" do
    assert_empty readers.excluding(@alice)
  end

  test "the others who read it, never its sender nor the one looking" do
    message = send_message(@chat, @alice, "dinner at 8")
    @chat.participant_for(@bob).read_up_to!(message)
    @chat.participant_for(@carol).read_up_to!(message)

    assert_equal [ @bob, @carol ], readers.excluding(@alice)
    assert_equal [ @carol ], readers.excluding(@bob)
  end

  test "a newer message nobody has read yet empties the line" do
    first = send_message(@chat, @alice, "dinner at 8")
    @chat.participant_for(@bob).read_up_to!(first)
    send_message(@chat, @carol, "I'll be late")

    assert_empty readers.excluding(@alice)
  end
end
