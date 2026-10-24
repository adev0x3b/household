# frozen_string_literal: true

module Conversations
  # Pushes a conversation's changes to everyone in it, each over their own
  # signed stream (`turbo_stream_from conversation, profile` on the
  # conversation page): a bubble is "mine" or "theirs" depending on who looks
  # at it, so one render per viewer. What changes the list of conversations
  # or the navbar's count goes over the profile's notifications stream, which
  # every page opens.
  #
  # DOM contract (see Views::Conversations::Show and ::Index):
  #   #conversation-<id>-header     the title and who's in it
  #   #conversation-<id>-messages   the thread (bubbles are appended to it)
  #   message_<id>                  one bubble (Views::Conversations::Bubble)
  #   message_<id>_reactions        its reactions (Views::Conversations::Reactions)
  #   #conversation-<id>-seen       who has read the newest message
  #   #conversation-row-<id>        the row on the index
  #   .messages-badge               the unread count, wherever Messages is listed
  #                                 (every copy at once: `targets:`)
  #
  # A request asks for it `later` (Conversations::BroadcastJob): the work
  # grows with the people in the conversation.
  class Broadcaster < ApplicationBroadcaster
    def self.later(event, subject, *arguments) = BroadcastJob.perform_later(event.to_s, subject, *arguments)

    def self.message_sent(message)
      quietly do
        message = Message.with_everything.find(message.id)
        conversation = message.conversation
        rows = RowFacts.new(conversation)
        readers = Readers.new(conversation)
        each_viewer(conversation) do |profile|
          stream_to([ conversation, profile ], :append, Views::Conversations::Bubble.new(message: message, viewer: profile),
                    target: Views::Conversations::Thread.dom_id(conversation))
          seen(conversation, profile, readers)
          row_and_badge(conversation, profile, rows)
        end
      end
    end

    # A reaction given or taken back: the chips under the bubble, for
    # everyone — not the bubble, whose pictures would be fetched again.
    def self.reactions_changed(message)
      quietly do
        message = Message.with_everything.find(message.id)
        each_viewer(message.conversation) do |profile|
          stream_to([ message.conversation, profile ], :update, Views::Conversations::Reactions.new(message: message, viewer: profile),
                    target: Views::Conversations::Reactions.dom_id(message))
        end
      end
    end

    # A message unsent: its bubble, for everyone.
    def self.message_changed(message)
      quietly do
        message = Message.with_everything.find(message.id)
        each_viewer(message.conversation) do |profile|
          stream_to([ message.conversation, profile ], :replace, Views::Conversations::Bubble.new(message: message, viewer: profile),
                    target: Views::Conversations::Bubble.dom_id(message))
        end
      end
    end

    def self.renamed(conversation)
      quietly do
        conversation = Conversation.includes(:participants).find(conversation.id)
        rows = RowFacts.new(conversation)
        each_viewer(conversation) do |profile|
          stream_to([ conversation, profile ], :replace, Views::Conversations::Header.new(conversation: conversation, viewer: profile),
                    target: Views::Conversations::Header.dom_id(conversation))
          row_and_badge(conversation, profile, rows)
        end
      end
    end

    # `reader` has read up to the newest message: the others see it under it;
    # the reader's own pages lose the unread count.
    def self.read(conversation, reader)
      quietly do
        conversation = Conversation.includes(:participants, :conversation_participants).find(conversation.id)
        rows = RowFacts.new(conversation)
        readers = Readers.new(conversation)
        each_viewer(conversation) do |profile|
          profile.id == reader.id ? row_and_badge(conversation, profile, rows) : seen(conversation, profile, readers)
        end
      end
    end

    def self.each_viewer(conversation)
      conversation.participants.each { |profile| as(profile) { yield profile } }
    end

    def self.seen(conversation, profile, readers)
      stream_to([ conversation, profile ], :replace, Views::Conversations::Seen.new(conversation: conversation, readers: readers.excluding(profile)),
                target: Views::Conversations::Seen.dom_id(conversation))
    end

    # What every participant's row and count say, read once for all of them.
    RowFacts = Struct.new(:conversation) do
      def summaries = @summaries ||= Summaries.new(conversation.participants, [ conversation ])
      def unread_for(profile) = (@unread ||= ::Messages::Unread.counts_for(conversation.participants)).fetch(profile.id, 0)
    end

    # The index's row and the navbar's count, over the profile's own stream.
    def self.row_and_badge(conversation, profile, rows)
      stream_to([ profile, :notifications ], :replace, Views::Conversations::Row.new(conversation: conversation, viewer: profile, summaries: rows.summaries),
                target: Views::Conversations::Row.dom_id(conversation))
      stream_to([ profile, :notifications ], :replace, Views::Conversations::Badge.new(count: rows.unread_for(profile)),
                targets: Views::Conversations::Badge::SELECTOR)
    end
    private_class_method :each_viewer, :seen, :row_and_badge
  end
end
