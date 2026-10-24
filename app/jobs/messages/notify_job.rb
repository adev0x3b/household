# frozen_string_literal: true

module Messages
  # A few seconds after a message is sent (Messages::Send::NOTIFY_AFTER),
  # tells each participant who still hasn't seen it: one notification per
  # conversation under their bell, refreshed (not multiplied) by every
  # message that follows, and pushed to their devices. Whoever had the
  # conversation open read it by then, and hears nothing.
  class NotifyJob < ApplicationJob
    def perform(message_id)
      message = Message.includes(conversation: :conversation_participants).find_by(id: message_id) or return
      return if message.deleted?

      message.conversation.conversation_participants.each do |participant|
        next if participant.profile_id == message.sender_id || participant.read?(message)

        Notifications::Deliver.call(
          recipient: participant.profile, kind: :message_received, subject: message.conversation, actor: message.sender,
          title: message.conversation.title_for(participant.profile),
          data: { scope: message.conversation.kind, detail: message.line,
                  unread: message.conversation.unread_count_for(participant.profile) },
          replace: Notification.unread.message_received.find_by(profile_id: participant.profile_id, subject: message.conversation)
        )
      end
    end
  end
end
