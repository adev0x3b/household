# frozen_string_literal: true

module Messages
  # Sends a message: saves it, pushes it to everyone's open pages
  # (Conversations::Broadcaster) and, a few seconds later, tells whoever
  # hasn't seen it by then (NotifyJob: a line under the bell, a push to
  # their devices). The sender's own page already shows it.
  #
  #   Messages::Send.call(conversation:, sender:, body: "…", images: [ … ], client_id: "…")
  #
  # Pictures are kept without their metadata (CleanPicture), and one that
  # can't be cleaned is refused, not kept as it came.
  #
  # `client_id` is the composer's idempotency key: the same send repeated
  # (a retry over a bad connection) returns the message already saved
  # instead of a second one. Returns the message; an invalid one unsaved,
  # with its errors.
  class Send
    NOTIFY_AFTER = 8.seconds

    def self.call(conversation:, sender:, body:, client_id:, images: [], notify: true)
      if (existing = conversation.messages.find_by(sender_id: sender.id, client_id: client_id))
        return existing
      end

      message = conversation.messages.new(sender: sender, body: body, client_id: client_id)
      pictures = images.map { CleanPicture.call(_1) }
      if (refused = pictures.find(&:failure?))
        message.errors.add(:base, refused.error)
        return message
      end
      message.images.attach(pictures.map(&:picture)) if pictures.any?
      return message unless message.save

      conversation.touch_last_message!(message)
      Conversations::Broadcaster.later(:message_sent, message)
      NotifyJob.set(wait: NOTIFY_AFTER).perform_later(message.id) if notify
      message
    rescue ActiveRecord::RecordNotUnique
      conversation.messages.find_by!(sender_id: sender.id, client_id: client_id)
    end
  end
end
