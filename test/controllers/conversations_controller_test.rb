# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    @alice, @bob, @carol = profiles(:alice), profiles(:bob), profiles(:carol)
    @chat = Conversation.household_conversation(households(:example))
    @direct = Conversation.direct_between(@alice, @bob)
    sign_in @alice
  end

  test "the list has the household's conversation, the ones begun and the housemates not yet written to" do
    send_message(@direct, @bob, "see you at 8")

    get conversations_path

    assert_response :success
    assert_select "#conversation-row-#{@chat.id} .conversation-row__title", text: "Example"
    assert_select "#conversation-row-#{@direct.id}.conversation-row--unread .conversation-row__preview", text: "Bob: see you at 8"
    assert_select "#conversation-row-#{@direct.id} .conversation-row__unread", text: "1"
    assert_select "form[action='#{conversations_path}'] input[name=profile_id][value='#{@carol.id}']"
    assert_select "form[action='#{conversations_path}'] button#conversation-row-profile-#{@carol.id} .conversation-row__title", text: "Carol"
    assert_select "a.navbar-link[href='#{conversations_path}'] .messages-badge [aria-hidden]", text: "1"
  end

  test "opening Messages only reads: the household's conversation is there from the day one joins" do
    assert_no_difference -> { Conversation.count + ConversationParticipant.count } do
      get conversations_path
    end
    assert_select "#conversation-row-#{conversations(:example_chat).id}"
  end

  test "a housemate's conversation is opened by a press, made the first time, never a stranger's" do
    assert_difference "Conversation.count", 1 do
      post conversations_path, params: { profile_id: @carol.id }
    end
    assert_redirected_to conversation_path(Conversation.direct_between(@alice, @carol))
    assert_response :see_other

    post conversations_path, params: { profile_id: profiles(:outsider).id }
    assert_response :not_found
  end

  test "opening a conversation shows its thread; reading it is the page's read receipt, which tells the others" do
    message = send_message(@direct, @bob, "hello there")
    Notifications::Deliver.call(recipient: @alice, kind: :message_received, subject: @direct, actor: @bob, title: "Bob", data: { scope: "direct" })

    streams = capture_turbo_stream_broadcasts([ @direct, @bob ]) do
      get conversation_path(@direct)
    end

    assert_response :success
    assert_select "turbo-cable-stream-source[channel='Turbo::StreamsChannel']"
    assert_select "#conversation-#{@direct.id}-header .page-header h1.page-title", text: "Bob"
    assert_select "#conversation-#{@direct.id}-header a.page-header__back[href=?]", conversations_path
    assert_select "#conversation-#{@direct.id}-messages[role=log]", 1, "a screen reader reads a message as it arrives"
    assert_select "#message_#{message.id}.message--theirs[data-message-id='#{message.id}'][data-mine=false] .message__text", text: "hello there"
    assert_select "[data-controller~=conversation][data-conversation-read-url-value=?]", conversation_read_receipt_path(@direct)
    assert_select "[data-controller~=reaction-picker] #reaction_picker", 1, "one picker of quick emoji, for every message"
    assert_select ".message [role=menu]", 0
    assert_select "#conversation-#{@direct.id}-older.conversation__older--start"
    assert_select ".conversation-composer input[name=client_id]"
    assert_select ".conversation-composer input[type=file][capture=environment][accept='image/*']"
    assert_select ".conversation-composer input[type=file][name='images[]'][multiple]"
    assert_select ".conversation-composer__attach", 2
    assert_select ".page-controls__action", 0
    assert_nil @direct.participant_for(@alice).reload.last_read_message_id, "a GET reads nothing: Turbo prefetches hovered rows"
    assert_predicate @alice.notifications.message_received.sole, :unread?
    assert_empty streams

    streams = capture_turbo_stream_broadcasts([ @direct, @bob ]) do
      perform_enqueued_jobs(only: Conversations::BroadcastJob) do
        post conversation_read_receipt_path(@direct), params: { message_id: message.id }, as: :json
      end
    end

    assert_response :no_content
    assert_equal message.id, @direct.participant_for(@alice).reload.last_read_message_id
    assert_not @alice.notifications.message_received.sole.unread?
    assert_equal([ "replace" ], streams.map { _1["action"] })
    assert_includes streams.first.to_html, "Seen"
  end

  test "a stranger to a direct conversation gets nothing" do
    sign_in @carol
    get conversations_path # a request that succeeds writes Carol's session; a 404 wouldn't
    assert_select "#conversation-row-#{@direct.id}", 0

    get conversation_path(@direct)
    assert_response :not_found

    post conversation_read_receipt_path(@direct), params: { message_id: 1 }, as: :json
    assert_response :not_found
    assert_nil @direct.participant_for(@alice).reload.last_read_message_id
  end

  test "earlier messages come a page at a time, above the ones shown" do
    (ConversationsController::PAGE + 3).times { |i| send_message(@chat, @bob, "message #{i}") }
    first_shown = @chat.messages.newest_first.limit(ConversationsController::PAGE).to_a.last

    get conversation_path(@chat)
    assert_select "a#conversation-#{@chat.id}-older[href='#{older_conversation_path(@chat, before: first_shown.id)}']"
    assert_select ".message", ConversationsController::PAGE

    get older_conversation_path(@chat, before: first_shown.id), as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=replace][target='conversation-#{@chat.id}-older'] .conversation__older--start"
    assert_select "turbo-stream[action=after][target='conversation-#{@chat.id}-older'] .message", 3
  end

  test "anyone renames the household's conversation, for everyone; blank takes the name back" do
    get conversation_path(@chat)
    assert_select "a.page-controls__action[href='#{edit_conversation_path(@chat)}']"

    get edit_conversation_path(@chat), as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals] input[name='conversation[name]']"

    streams = capture_turbo_stream_broadcasts([ @chat, @bob ]) do
      perform_enqueued_jobs(only: Conversations::BroadcastJob) do
        patch conversation_path(@chat), params: { conversation: { name: "The Examples" } }, as: :turbo_stream
      end
    end
    assert_response :success
    assert_equal "The Examples", @chat.reload.name
    assert_includes streams.map { _1["target"] }, "conversation-#{@chat.id}-header"
    assert_includes streams.first.to_html, "The Examples"

    patch conversation_path(@chat), params: { conversation: { name: "" } }, as: :turbo_stream
    assert_nil @chat.reload.name

    patch conversation_path(@direct), params: { conversation: { name: "Us" } }, as: :turbo_stream
    assert_response :forbidden
    assert_nil @direct.reload.name
  end
end
