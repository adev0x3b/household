# frozen_string_literal: true

require "test_helper"

class ConversationReadReceiptsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice, @bob = profiles(:alice), profiles(:bob)
    @direct = Conversation.direct_between(@alice, @bob)
    sign_in @alice
  end

  test "the page says what it saw as it arrives, or the newest when it names nothing" do
    first = send_message(@direct, @bob, "one")
    second = send_message(@direct, @bob, "two")

    post conversation_read_receipt_path(@direct), params: { message_id: first.id }, as: :json
    assert_response :no_content
    assert_equal first.id, @direct.participant_for(@alice).reload.last_read_message_id

    post conversation_read_receipt_path(@direct), as: :json
    assert_equal second.id, @direct.participant_for(@alice).reload.last_read_message_id
  end

  test "a message that is gone, or a conversation with nothing in it, moves the receipt nowhere" do
    post conversation_read_receipt_path(@direct), params: { message_id: 1 }, as: :json
    assert_response :no_content
    assert_nil @direct.participant_for(@alice).reload.last_read_message_id
  end

  test "a stranger to a direct conversation can't say they read it" do
    sign_in profiles(:carol)
    get conversations_path # a request that succeeds writes Carol's session; a 404 wouldn't

    post conversation_read_receipt_path(@direct), params: { message_id: 1 }, as: :json
    assert_response :not_found
  end
end
