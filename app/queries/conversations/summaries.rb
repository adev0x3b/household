# frozen_string_literal: true

module Conversations
  # What a conversation's row on the list says, for many rows at once: the
  # last thing said (and who said it) and how much each viewer hasn't read
  # (Messages::Unread, counted per conversation). A few queries, whatever
  # the number of rows: one person's list, or one conversation pushed to
  # everyone in it.
  #
  #   summaries = Conversations::Summaries.new(viewer, conversations)            # a list
  #   summaries = Conversations::Summaries.new(conversation.participants, [ conversation ])   # a push
  #   summaries.last_message(conversation)   # => Message, or nil
  #   summaries.unread(conversation, viewer) # => Integer
  class Summaries
    def initialize(viewers, conversations)
      @viewers = Array(viewers)
      @ids = conversations.map(&:id)
    end

    def last_message(conversation) = last_messages[conversation.id]
    def unread(conversation, viewer) = unread_counts.fetch([ conversation.id, viewer.id ], 0)

    private

    def last_messages
      @last_messages ||= Message.where(conversation_id: @ids)
        .select("DISTINCT ON (messages.conversation_id) messages.*").order(:conversation_id, id: :desc)
        .includes(:sender).index_by(&:conversation_id)
    end

    def unread_counts
      @unread_counts ||= Messages::Unread.of(@viewers).where(conversation_id: @ids)
        .group(:conversation_id, "conversation_participants.profile_id").count
    end
  end
end
