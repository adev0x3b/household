# frozen_string_literal: true

# Pushes a chat's live updates over its signed stream with the same Phlex
# components as the page, so a push looks like a reload. A chat is one
# person's, and the reply job already runs in their language and zone.
module Assistant
  class Broadcaster < ApplicationBroadcaster
    def self.start(chat) = quietly { stream_to(chat, :append, Views::Assistant::Chats::Reply.new(text: nil), target: thread) }

    # Also instrumented as "reply_text.assistant", which AssistantEval::Recorder
    # follows during an eval run. It costs nothing when nobody listens.
    def self.reply_text(chat, text)
      ActiveSupport::Notifications.instrument("reply_text.assistant", chat_id: chat.id, text: text)
      quietly { stream_to(chat, :replace, Views::Assistant::Chats::Reply.new(text: text), target: reply) }
    end

    def self.finish(chat, message)
      quietly do
        stream_to(chat, :remove, target: reply)
        if message&.content.present?
          stream_to(chat, :append, Views::Assistant::Chats::MessageBubble.new(role: "assistant", content: message.content), target: thread)
        end
        composer(chat)
      end
    end

    def self.failure(chat, failure)
      quietly do
        stream_to(chat, :remove, target: reply)
        stream_to(chat, :append, Views::Assistant::Chats::ReplyFailureNotice.new(failure: failure), target: thread)
        composer(chat)
      end
    end

    # One row per read (searches, lookups); changes show as their card instead.
    def self.tool_activity(chat, tool_name, arguments, result)
      return if result[:ok] && Assistant::ChangeTool.write_tool_names.include?(tool_name)

      quietly do
        stream_to(chat, :before, Views::Assistant::Chats::ToolActivity.new(tool_name: tool_name, arguments: arguments, result: result), target: reply)
      end
    end

    # The change set's card, moved to the end of the thread each time it changes.
    def self.change_set(set)
      quietly do
        stream_to(set.chat, :remove, target: Views::Assistant::Chats::ChangeSetCard.dom_id(set))
        card = Views::Assistant::Chats::ChangeSetCard.new(change_set: set, targets: ChangeSets::RowTargets.load(set))
        stream_to(set.chat, :before, card, target: reply)
      end
    end

    # A chat is its owner's alone, so the composer pushed is drawn for them.
    def self.composer(chat)
      composer = Views::Assistant::Chats::Composer.new(chat: chat, messages_left: MessageAllowance.new(chat.profile.household).left,
                                                       attach: Pundit.policy!(chat.profile, chat).attach?)
      stream_to(chat, :replace, composer, target: Views::Assistant::Chats::Composer::ID)
    end

    # Where a push lands, by the ids the page and the reply give themselves.
    def self.thread = Views::Assistant::Chats::Show::THREAD_ID
    def self.reply = Views::Assistant::Chats::Reply::ID

    private_class_method :composer, :thread, :reply
  end
end
