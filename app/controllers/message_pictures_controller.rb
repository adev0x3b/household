# frozen_string_literal: true

# A message's pictures, to the people in its conversation and nobody else
# (ServesAttachments):
#   show      the shrunk copy a bubble draws (Message's :shown variant)
#   original  the picture as sent, opened on a tap — without its metadata
#             (Messages::CleanPicture)
# Someone else's message is a 404.
class MessagePicturesController < ApplicationController
  include ServesAttachments

  before_action :set_picture

  def show = send_attachment(@picture.variant(:shown).processed.image.blob)

  def original = send_attachment(@picture.blob)

  private

  def set_picture
    message = Message.where(conversation: policy_scope(Conversation)).find(params[:message_id])
    authorize message.conversation, :show?
    @picture = message.images.find(params[:id])
  end
end
