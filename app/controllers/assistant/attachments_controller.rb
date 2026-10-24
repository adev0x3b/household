# frozen_string_literal: true

# A photo sent to the assistant is usually a lab report, which is health
# data, so only the chat's owner is served it (ServesAttachments). Someone
# else's chat is a 404.
class Assistant::AttachmentsController < ApplicationController
  include AssistantEnabled
  include ServesAttachments

  def show
    chat = policy_scope(Assistant::Chat).find(params[:chat_id])
    authorize chat, :show?

    attachment = ActiveStorage::Attachment.where(record_type: Assistant::Message.polymorphic_name, record_id: chat.assistant_messages.select(:id))
      .find(params[:id])
    send_attachment(attachment.blob)
  end
end
