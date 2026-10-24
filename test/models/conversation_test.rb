# frozen_string_literal: true

require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  setup do
    @household = households(:example)
    @alice, @bob, @carol = profiles(:alice), profiles(:bob), profiles(:carol)
  end

  test "the household has one conversation, with everyone joined in" do
    chat = Conversation.household_conversation(@household)

    assert_predicate chat, :household?
    assert_equal chat, Conversation.household_conversation(@household)
    assert_equal [ @alice, @bob, @carol ].map(&:id).sort, chat.participants.map(&:id).sort
    assert_equal "Example", chat.title_for(@alice)
    assert_raises(ActiveRecord::RecordNotUnique) { Conversation.create!(household: @household, kind: :household) }
  end

  test "a member who joins later is let in, and the first member of a household makes it" do
    erin = Profile.create!(household: @household, username: "erin", email: "erin@example.com", password: "a-long-password")
    assert_no_difference "Conversation.count" do
      assert Conversation.household_conversation(@household).participant?(erin)
    end

    fresh = Household.create!(name: "Fresh")
    first = Profile.create!(household: fresh, username: "fay", email: "fay@example.com", password: "a-long-password")
    assert Conversation.household_conversation(fresh).participant?(first)
    assert Conversation.household.find_by!(household: fresh).participant?(first)
  end

  test "a direct conversation is one per pair, whoever opens it" do
    one = Conversation.direct_between(@alice, @bob)
    assert_predicate one, :direct?
    assert_equal one, Conversation.direct_between(@bob, @alice)
    assert_equal [ @alice, @bob ].map(&:id).sort, one.participants.map(&:id).sort
    assert_equal "Bob", one.title_for(@alice)
    assert_equal "Alice", one.title_for(@bob)
    assert_equal @bob, one.counterpart_of(@alice)
    assert_raises(ArgumentError) { Conversation.direct_between(@alice, @alice) }
  end

  test "nothing crosses households" do
    assert_no_difference "Conversation.count" do
      assert_raises(ActiveRecord::RecordInvalid) { Conversation.direct_between(@alice, profiles(:outsider)) }
    end

    chat = Conversation.household_conversation(@household)
    participant = chat.conversation_participants.new(profile: profiles(:outsider))
    assert_not participant.valid?
    assert participant.errors.of_kind?(:profile, :outside_household)
  end

  test "its name is the household's until renamed, and a direct one has none" do
    chat = Conversation.household_conversation(@household)
    chat.update!(name: "  The Examples  ")
    assert_equal "The Examples", chat.title_for(@alice)
    chat.update!(name: "")
    assert_equal "Example", chat.title_for(@alice)
    assert_not chat.update(name: "x" * 61)

    direct = Conversation.direct_between(@alice, @bob)
    assert_not direct.update(name: "Us")
  end

  test "a direct conversation is called after the other person, someone who left once they are gone" do
    direct = Conversation.direct_between(@alice, @bob)
    assert_equal @bob.display_name, direct.title_for(@alice)
    assert_nil Conversation.household_conversation(@household).counterpart_of(@alice)

    assert_no_difference -> { direct.conversation_participants.count } do
      direct.sync_household_participants!
    end
    direct.conversation_participants.find_by!(profile: @bob).delete
    assert_equal "Someone who left", direct.reload.title_for(@alice)
  end

  test "a person's conversations are those they take part in, newest news first" do
    chat = Conversation.household_conversation(@household)
    with_bob = Conversation.direct_between(@alice, @bob)
    with_carol = Conversation.direct_between(@alice, @carol)
    bob_and_carol = Conversation.direct_between(@bob, @carol)
    send_message(with_carol, @carol, "first")
    send_message(with_bob, @bob, "later")

    assert_equal [ with_bob, with_carol, chat ], Conversation.accessible_by(@alice).recent_first.to_a
    assert_not_includes Conversation.accessible_by(@alice), bob_and_carol
  end

  test "unread is what others said after the newest message one has seen" do
    direct = Conversation.direct_between(@alice, @bob)
    first = send_message(direct, @bob, "one")
    send_message(direct, @bob, "two")
    send_message(direct, @alice, "mine doesn't count")
    assert_equal 2, direct.unread_count_for(@alice)
    assert_equal 1, direct.unread_count_for(@bob)

    participant = direct.participant_for(@alice)
    assert participant.read_up_to!(first)
    assert_equal 1, direct.reload.unread_count_for(@alice)
    assert_not participant.read_up_to!(first), "reading never goes backwards"
    assert_equal 1, Messages::Unread.count_for(@alice)
  end

  test "two reads arriving together can't move a receipt backwards" do
    direct = Conversation.direct_between(@alice, @bob)
    first = send_message(direct, @bob, "one")
    second = send_message(direct, @bob, "two")
    early = direct.participant_for(@alice) # loaded before either read, as two requests would
    late = ConversationParticipant.find(early.id)

    assert late.read_up_to!(second)
    assert_not early.read_up_to!(first), "it still thinks nothing was read, the table knows better"
    assert_equal second.id, early.reload.last_read_message_id
  end
end
