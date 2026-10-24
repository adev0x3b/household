# frozen_string_literal: true

require "application_system_test_case"

# Housemates talking: what one sends is on the other's screen at once, and
# a reaction comes back the same way (Conversations::Broadcaster, from its
# job; Action Cable's test adapter still delivers in-process).
class MessagesTest < ApplicationSystemTestCase
  test "a message reaches the housemate who has the conversation open, and their reaction comes back" do
    conversation = Conversation.household_conversation(households(:example))

    using_session(:bob) do
      sign_in profiles(:bob)
      visit conversation_path(conversation)
      assert_listening
    end
    sign_in profiles(:alice)
    visit conversation_path(conversation)
    assert_text I18n.t("conversations.show.empty")
    assert_listening

    perform_enqueued_jobs(only: Conversations::BroadcastJob) do
      fill_in I18n.t("conversations.composer.placeholder"), with: "Dinner at 8?"
      click_on I18n.t("conversations.composer.send")
      assert_selector ".message--mine", text: "Dinner at 8?"
      assert_no_text I18n.t("conversations.show.empty")

      using_session(:bob) do
        assert_no_text I18n.t("conversations.show.empty")
        within(".message--theirs", text: "Dinner at 8?") { click_on I18n.t("conversations.reactions.add") }
        within("#reaction_picker") { click_on I18n.t("conversations.reactions.react_with", emoji: "👍") }
        assert_selector ".message--theirs .message__reactions", text: "👍"
        assert_accessible "a conversation, with a reaction"
      end

      within(".message--mine", text: "Dinner at 8?") { assert_selector ".message__reactions", text: "👍" }
    end
  end

  test "going back from a conversation that was read shows it read, in the list and on the Messages badge" do
    alice = profiles(:alice)
    conversation = Conversation.household_conversation(households(:example))
    send_message(conversation, profiles(:bob), "Bins tonight?")

    sign_in alice
    visit conversations_path
    assert_selector ".conversation-row--unread", text: "Bins tonight?"
    assert_selector ".messages-badge", text: "1"

    click_on "Bins tonight?"
    assert_selector ".message--theirs", text: "Bins tonight?"
    assert_eventually { Messages::Unread.count_for(alice).zero? }

    page.go_back
    assert_selector ".conversation-row", text: "Bins tonight?"
    assert_no_selector ".conversation-row--unread"
    assert_no_selector ".messages-badge"
  end
end
