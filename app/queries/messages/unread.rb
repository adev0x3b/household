# frozen_string_literal: true

module Messages
  # How many messages from others a person hasn't seen, over all their
  # conversations (the navbar's count), from each participation's read
  # receipt — one query, for one person or for everyone a push reaches.
  class Unread
    def self.count_for(profile) = counts_for([ profile ]).fetch(profile.id, 0)

    # { profile_id => count } (absent: none unread).
    def self.counts_for(profiles) = of(profiles).group("conversation_participants.profile_id").count

    # The messages each of `profiles` hasn't read, one row per message and
    # reader: sent by someone else after the reader's receipt. Grouped by
    # `conversation_participants.profile_id` it counts per reader.
    def self.of(profiles)
      Message.joins(conversation: :conversation_participants)
        .where(conversation_participants: { profile_id: profiles.map(&:id) })
        .where("messages.sender_id <> conversation_participants.profile_id")
        .where("messages.id > COALESCE(conversation_participants.last_read_message_id, 0)")
    end
  end
end
