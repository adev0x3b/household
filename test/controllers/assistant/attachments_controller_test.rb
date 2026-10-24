# frozen_string_literal: true

require "test_helper"

# A photo sent to the assistant — health data, as a rule — reaches the
# chat's owner alone.
class Assistant::AttachmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = profiles(:alice)
    @chat = assistant_chat(@alice)
    message = @chat.assistant_messages.create!(role: "user", content: "my results")
    message.attachments.attach(io: file_fixture("lab_report_sample.png").open, filename: "report.png", content_type: "image/png")
    @photo = message.attachments.sole
  end

  test "the chat shows the photo by its own route, and its owner gets it" do
    sign_in @alice

    get assistant_chat_path(@chat)
    assert_select "img.assistant-message__image[src=?]", assistant_chat_attachment_path(@chat, @photo)

    get assistant_chat_attachment_path(@chat, @photo)
    assert_response :success
    assert_equal file_fixture("lab_report_sample.png").binread, response.body
    assert_equal "max-age=#{1.year.to_i}, private, immutable", response.headers["Cache-Control"]
  end

  test "anyone else gets nothing, even with the chat's address" do
    sign_in profiles(:bob)
    get assistant_chats_path # a request that succeeds writes the session; a 404 wouldn't

    get assistant_chat_attachment_path(@chat, @photo)
    assert_response :not_found
  end
end
