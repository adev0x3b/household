# frozen_string_literal: true

module ConversationBuilders
  # A message sent without telling anyone (no NotifyJob), for tests about something else.
  def send_message(conversation, sender, body = "hello", images: [], notify: false)
    Messages::Send.call(conversation: conversation, sender: sender, body: body, images: images, client_id: SecureRandom.uuid, notify: notify)
  end

  def picture_upload = fixture_file_upload("lab_report_sample.png", "image/png")
end
