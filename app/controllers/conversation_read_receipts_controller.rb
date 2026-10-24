# frozen_string_literal: true

# What the reader has seen of a conversation, posted by its page as
# messages arrive while it is visible (conversation_controller.js): the
# receipt moves up to the message named, or to the newest when none is,
# the bell's line about the conversation is read, and the others in it are
# told, so the sender sees "Seen".
class ConversationReadReceiptsController < ApplicationController
  def create
    conversation = policy_scope(Conversation).includes(:household, :participants, :conversation_participants).find(params[:conversation_id])
    authorize conversation, :read?

    message = params[:message_id].present? ? conversation.messages.find_by(id: params[:message_id]) : conversation.messages.newest_first.first
    mark_read!(conversation, message)
    head :no_content
  end

  private

  def mark_read!(conversation, message)
    return if message.nil?

    changed = conversation.participant_for(current_profile).read_up_to!(message)
    read_notifications = current_profile.notifications.unread.message_received.where(subject: conversation).update_all(read_at: Time.current)
    Notifications::Broadcaster.badge(current_profile) if read_notifications.positive?
    Conversations::Broadcaster.later(:read, conversation, current_profile) if changed
  end
end
