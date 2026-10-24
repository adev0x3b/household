# frozen_string_literal: true

module Conversations
  # Who has read a conversation's newest message, as the line under it says:
  # never its sender, and never the person looking, so each viewer gets the
  # others. The newest message is read once for every viewer of a push.
  #
  #   readers = Conversations::Readers.new(conversation)
  #   readers.excluding(viewer)  # => [Profile, …] by name
  class Readers
    def initialize(conversation)
      @conversation = conversation
    end

    def excluding(viewer)
      return [] unless newest

      @conversation.conversation_participants.select { |p| p.profile_id != viewer.id && p.profile_id != newest.sender_id && p.read?(newest) }
        .filter_map { |p| @conversation.participants.find { |person| person.id == p.profile_id } }
        .sort_by(&:display_name)
    end

    private

    def newest
      return @newest if defined?(@newest)

      @newest = @conversation.messages.newest_first.first
    end
  end
end
