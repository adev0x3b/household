# frozen_string_literal: true

class Views::Assistant::Chats::MessageBubble < Views::Base
  def initialize(role:, content:, attachments: [])
    @role = role.to_s
    # A photo's message carries the text read from it after the caption. It
    # is folded away, because the user wrote the caption and not the text.
    message = ::Assistant::PhotoMessage.new(::Assistant::ModelReply.new(content).answer)
    @photo_text = message.photo_text
    @content = message.caption
    @attachments = attachments
  end

  def view_template
    div(class: "assistant-message assistant-message--#{@role}") do
      div(class: "assistant-message__bubble") do
        render_attachments
        render Views::Assistant::Chats::Markdown.new(@content)
        render_photo_text if @photo_text
      end
    end
  end

  private

  def render_photo_text
    details(class: "assistant-message__photo-text") do
      summary { t("assistant.thread.photo_text") }
      pre { @photo_text }
    end
  end

  # Photos come through Assistant::AttachmentsController, which shows them
  # to the chat's owner alone. Several pages of a report sit as a row of
  # thumbnails; one photo takes the full width.
  def render_attachments
    return unless @attachments.respond_to?(:each)

    images = @attachments.select { |attachment| attachment.respond_to?(:representable?) && attachment.image? }
    return if images.empty?

    div(class: [ "assistant-message__images", ("assistant-message__images--several" if images.size > 1) ]) do
      images.each do |image|
        img(src: assistant_chat_attachment_path(image.record.assistant_chat_id, image), class: "assistant-message__image",
            alt: t("assistant.thread.attached_image_alt"))
      end
    end
  end
end
