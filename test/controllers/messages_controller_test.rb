# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    @alice, @bob, @carol = profiles(:alice), profiles(:bob), profiles(:carol)
    @direct = Conversation.direct_between(@alice, @bob)
    sign_in @alice
  end

  test "sending a message shows it to both, at once, in each one's language, and tells the other later" do
    @bob.update!(locale: "it")
    client_id = SecureRandom.uuid

    streams = capture_turbo_stream_broadcasts([ @direct, @bob ]) do
      perform_enqueued_jobs(only: Conversations::BroadcastJob) do
        assert_enqueued_with(job: Messages::NotifyJob) do
          post conversation_messages_path(@direct), params: { body: "Dinner at 8?", client_id: client_id }, as: :turbo_stream
        end
      end
    end

    assert_response :created
    message = @direct.messages.sole
    assert_equal [ "Dinner at 8?", client_id, @alice ], [ message.body, message.client_id, message.sender ]
    assert_select "turbo-stream[action=append][target='conversation-#{@direct.id}-messages'] #message_#{message.id}.message--mine"
    assert_select "turbo-stream[action=replace][target='conversation-#{@direct.id}-seen']"
    bubble = streams.find { _1["target"] == "conversation-#{@direct.id}-messages" }
    assert_includes bubble.to_html, "message--theirs"
    assert_includes bubble.to_html, "Reagisci"
    assert_equal message.created_at, @direct.reload.last_message_at
  end

  test "the same send twice saves one message" do
    client_id = SecureRandom.uuid

    assert_difference "Message.count", 1 do
      2.times { post conversation_messages_path(@direct), params: { body: "once", client_id: client_id }, as: :turbo_stream }
    end
    assert_response :created
  end

  test "pictures go with the message, shrunk, by a path that is right on every page they're pushed to" do
    streams = capture_turbo_stream_broadcasts([ @direct, @bob ]) do
      perform_enqueued_jobs(only: Conversations::BroadcastJob) do
        post conversation_messages_path(@direct), params: { body: "", images: [ picture_upload, picture_upload ], client_id: SecureRandom.uuid }, as: :turbo_stream
      end
    end

    assert_response :created
    message = @direct.messages.sole
    assert_equal 2, message.images.count
    assert_select "turbo-stream[action=append] .message__pictures--several img.message__picture", 2
    assert_select "turbo-stream[action=append] a.message__picture-link[target=_blank]", 2
    first = message.images.first
    assert_select "turbo-stream[action=append] img.message__picture[src=?]", message_picture_path(message, first)
    assert_select "turbo-stream[action=append] a.message__picture-link[href=?]", original_message_picture_path(message, first)
    pushed = streams.find { _1["target"] == "conversation-#{@direct.id}-messages" }.to_html
    assert_includes pushed, %(src="#{message_picture_path(message, first)}")
    assert_not_includes pushed, "example.org"
  end

  test "a person sending too fast waits, and a housemate on the same address doesn't" do
    counting_rate_limits do
      30.times { post conversation_messages_path(@direct), params: { body: "hi", client_id: SecureRandom.uuid }, as: :turbo_stream }
      assert_response :created

      post conversation_messages_path(@direct), params: { body: "hi", client_id: SecureRandom.uuid }, as: :turbo_stream
      assert_response :too_many_requests
      assert_includes response.body, I18n.t("rate_limit.exceeded")

      sign_in @bob
      post conversation_messages_path(@direct), params: { body: "slow down", client_id: SecureRandom.uuid }, as: :turbo_stream
      assert_response :created
    end
  end

  test "too many pictures, or ones that aren't, are refused" do
    too_many = Array.new(Message::MAX_IMAGES + 1) { picture_upload }
    assert_no_difference "Message.count" do
      post conversation_messages_path(@direct), params: { images: too_many, client_id: SecureRandom.uuid }, as: :turbo_stream
    end
    assert_response :unprocessable_content
    assert_includes response.body, "At most #{Message::MAX_IMAGES} photos"

    assert_no_difference "Message.count" do
      text = Rack::Test::UploadedFile.new(StringIO.new("not a picture"), "text/plain", original_filename: "notes.txt")
      post conversation_messages_path(@direct), params: { images: [ text ], client_id: SecureRandom.uuid }, as: :turbo_stream
    end
    assert_response :unprocessable_content
    assert_includes response.body, ERB::Util.html_escape(I18n.t("activerecord.errors.models.message.attributes.base.not_a_picture"))
  end

  test "a picture that can't be cleared of where it was taken is refused, and nothing is sent" do
    assert_no_difference [ "Message.count", "ActiveStorage::Blob.count" ] do
      broken = Rack::Test::UploadedFile.new(StringIO.new("\xFF\xD8\xFF\xE0 and no more".b), "image/jpeg", original_filename: "photo.jpg")
      post conversation_messages_path(@direct), params: { body: "look", images: [ broken ], client_id: SecureRandom.uuid }, as: :turbo_stream
    end

    assert_response :unprocessable_content
    assert_includes response.body, ERB::Util.html_escape(I18n.t("activerecord.errors.models.message.attributes.base.not_cleaned"))
  end

  test "with pictures off, words only" do
    household = demo_household
    alex, sam = household.profiles.order(:id).first(2)
    sign_in alex
    chat = Conversation.household_conversation(household)

    with_env("PICTURES" => "off") do
      get conversation_path(chat)
      assert_select ".conversation-composer__attach", 0
      assert_select ".conversation-composer input[type=file]", 0

      post conversation_messages_path(chat), params: { body: "hi", images: [ picture_upload ], client_id: SecureRandom.uuid }, as: :turbo_stream
      assert_response :unprocessable_content
      assert_includes response.body, I18n.t("conversations.errors.pictures_off")
      assert_equal 0, chat.messages.count

      post conversation_messages_path(chat), params: { body: "hi #{sam.display_name}", client_id: SecureRandom.uuid }, as: :turbo_stream
      assert_response :created
    end
  end

  test "an empty message, and one to a conversation one isn't in, are refused" do
    assert_no_difference "Message.count" do
      post conversation_messages_path(@direct), params: { body: "   ", client_id: SecureRandom.uuid }, as: :turbo_stream
    end
    assert_response :unprocessable_content

    sign_out :profile
    sign_in @carol
    post conversation_messages_path(@direct), params: { body: "let me in", client_id: SecureRandom.uuid }, as: :turbo_stream
    assert_response :not_found
  end

  test "a message is unsent by its sender alone, for everyone" do
    message = send_message(@direct, @alice, "oops")
    message.message_reactions.create!(profile: @bob, emoji: "😂")

    sign_out :profile
    sign_in @bob
    delete message_path(message), as: :turbo_stream
    assert_response :forbidden
    assert_not message.reload.deleted?

    sign_out :profile
    sign_in @alice
    streams = capture_turbo_stream_broadcasts([ @direct, @bob ]) do
      perform_enqueued_jobs(only: Conversations::BroadcastJob) do
        delete message_path(message), as: :turbo_stream
      end
    end
    assert_response :success
    assert_predicate message.reload, :deleted?
    assert_select "turbo-stream[action=replace][target='message_#{message.id}'] .message--deleted .message__text--deleted", text: "Message unsent"
    assert_select "turbo-stream .message__reaction", 0
    assert_equal([ "message_#{message.id}" ], streams.map { _1["target"] })
  end

  test "a reaction is given with a tap and taken back with another, for everyone to see" do
    message = send_message(@direct, @bob, "look")

    streams = capture_turbo_stream_broadcasts([ @direct, @bob ]) do
      perform_enqueued_jobs(only: Conversations::BroadcastJob) do
        post message_reaction_path(message, emoji: "👍"), as: :turbo_stream
      end
    end
    assert_response :success
    assert_equal [ "👍" ], message.message_reactions.pluck(:emoji)
    assert_select "turbo-stream[action=update][target='message_#{message.id}_reactions'] form:has(input[name=_method][value=delete]) .message__reaction--mine[aria-pressed=true] .message__reaction-count", text: "1"
    assert_select "turbo-stream .message__bubble", 0, "a reaction never re-renders the bubble (its pictures would load again)"
    assert_equal([ "message_#{message.id}_reactions" ], streams.map { _1["target"] })
    assert_includes streams.sole.to_html, %(class="message__reaction" title="Alice")

    post message_reaction_path(message, emoji: "👍"), as: :turbo_stream
    assert_equal 1, message.message_reactions.count, "once per emoji"

    post message_reaction_path(message, emoji: "nope"), as: :turbo_stream
    assert_response :unprocessable_content

    delete message_reaction_path(message, emoji: "👍"), as: :turbo_stream
    assert_response :success
    assert_equal 0, message.message_reactions.count
    assert_select "turbo-stream .message__reaction", 0

    sign_out :profile
    sign_in @carol
    post message_reaction_path(message, emoji: "👍"), as: :turbo_stream
    assert_response :not_found
  end
end
