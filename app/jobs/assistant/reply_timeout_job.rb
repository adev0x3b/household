# frozen_string_literal: true

# A reply that never came. It is queued with every message, to run when
# Assistant::Chat::REPLY_TIMEOUT has passed; if the message's claim still
# holds the chat by then, its reply never ran or never ended: the
# assistant's own worker isn't running, or died mid-turn. The chat is
# freed, the thread says no answer came, and whoever runs the app is told.
#
# It runs on the general queue, not the assistant's, so it still runs
# when the assistant's worker is the one missing.
class Assistant::ReplyTimeoutJob < ApplicationJob
  queue_as :default

  # Reported for whoever runs the app, with a message that is the same
  # every time so a missing worker is one entry, however many replies wait.
  class Stalled < StandardError; end

  def perform(chat, claimed_at)
    return unless chat.release_reply!(claimed_at)

    I18n.with_locale(chat.locale) do
      Assistant::Broadcaster.failure(chat, chat.reply_failures.create!(reason: :stalled))
    end
    Rails.error.report(Stalled.new("A reply waited #{Assistant::Chat::REPLY_TIMEOUT.inspect} without ending: check that the worker " \
                                   "for the \"assistant\" queue is running."),
                       handled: true, context: { chat_id: chat.id })
  end
end
