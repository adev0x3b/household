# frozen_string_literal: true

module Conversations
  # Pushes a conversation's change to everyone in it, off the request that
  # made it: the household's conversation renders a bubble, a
  # "seen", a row and a count for each of its people, and whoever sent the
  # message shouldn't wait for them all — their own page has the response
  # already. One conversation's pushes run one at a time, in the order they
  # were made, so a bubble never overtakes the one before it.
  #
  #   Conversations::Broadcaster.later(:message_sent, message)
  class BroadcastJob < ApplicationJob
    EVENTS = %w[message_sent message_changed reactions_changed renamed read].freeze

    limits_concurrency to: 1, key: ->(_event, subject, *) { subject.is_a?(Message) ? subject.conversation : subject }

    def perform(event, subject, *arguments)
      raise ArgumentError, "unknown conversation event #{event.inspect}" unless EVENTS.include?(event)

      Broadcaster.public_send(event, subject, *arguments)
    end
  end
end
