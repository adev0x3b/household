# frozen_string_literal: true

# Sending a message (text, pictures, or both) and unsending one's own.
class MessagesController < ApplicationController
  # A person types a few messages a minute; a script doesn't get further.
  rate_limit_per_person to: 30, within: 1.minute, only: :create

  def create
    conversation = policy_scope(Conversation).includes(:conversation_participants).find(params[:conversation_id])
    message = Message.new(conversation: conversation)
    authorize message, :create?

    images = Array(params[:images]).compact_blank
    return refuse(t("conversations.errors.pictures_off")) if images.any? && !policy(message).attach?
    return refuse(t("conversations.errors.too_many_pictures", max: Message::MAX_IMAGES)) if images.size > Message::MAX_IMAGES

    message = Messages::Send.call(conversation: conversation, sender: current_profile, body: params[:body], images: images, client_id: client_id)
    return refuse(message.errors.full_messages.to_sentence) unless message.persisted?

    message = Message.with_everything.find(message.id)
    render turbo_stream: [
      turbo_stream.append(Views::Conversations::Thread.dom_id(conversation), Views::Conversations::Bubble.new(message: message, viewer: current_profile)),
      turbo_stream.replace(Views::Conversations::Seen.dom_id(conversation),
                           Views::Conversations::Seen.new(conversation: conversation,
                                                          readers: Conversations::Readers.new(conversation).excluding(current_profile)))
    ], status: :created
  end

  def destroy
    message = Message.joins(:conversation).merge(Conversation.accessible_by(current_profile)).find(params[:id])
    authorize message

    message.unsend!
    Conversations::Broadcaster.later(:message_changed, message)
    message = Message.with_everything.find(message.id)
    render turbo_stream: turbo_stream.replace(Views::Conversations::Bubble.dom_id(message),
                                              Views::Conversations::Bubble.new(message: message, viewer: current_profile))
  end

  private

  # The composer's own, or one minted here for a client that sent none.
  def client_id
    id = params[:client_id].to_s
    id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) ? id : SecureRandom.uuid
  end
end
