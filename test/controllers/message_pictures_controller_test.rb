# frozen_string_literal: true

require "test_helper"

# A message's pictures reach the people in its conversation, and nobody
# else: not a housemate outside it, not anyone holding an old URL.
class MessagePicturesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice, @bob, @carol = profiles(:alice), profiles(:bob), profiles(:carol)
    @direct = Conversation.direct_between(@alice, @bob)
    @message = send_message(@direct, @bob, "look", images: [ picture_upload ])
    @picture = @message.images.sole
  end

  test "the people in the conversation get the shrunk copy and the one sent, kept by their browser only" do
    sign_in @alice

    get message_picture_path(@message, @picture)
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "max-age=#{1.year.to_i}, private, immutable", response.headers["Cache-Control"]
    assert_match(/\Ainline/, response.headers["Content-Disposition"])

    get original_message_picture_path(@message, @picture)
    assert_response :success
    assert_equal @picture.blob.download, response.body
  end

  test "a housemate outside the conversation, or someone signed out, gets nothing" do
    sign_in @carol
    get conversations_path # a request that succeeds writes Carol's session; a 404 wouldn't
    get message_picture_path(@message, @picture)
    assert_response :not_found
    get original_message_picture_path(@message, @picture)
    assert_response :not_found

    sign_out :profile
    get original_message_picture_path(@message, @picture)
    assert_redirected_to new_profile_session_path
  end

  test "an unsent message's pictures are gone" do
    sign_in @alice
    @message.unsend!

    get original_message_picture_path(@message, @picture)
    assert_response :not_found
  end

  test "Active Storage's own routes serve nothing: their URLs never expire and need no sign-in" do
    assert_raises(NoMethodError) { rails_blob_path(@picture) }
    assert_empty(Rails.application.routes.routes.select { _1.path.spec.to_s.include?("active_storage") })
  end
end
