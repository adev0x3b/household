# frozen_string_literal: true

# The messages shown, oldest first. New ones are appended to it by the
# sender's own response and by the broadcast, so twice for the sender, and
# Turbo keeps one by the bubble's id. It is a log, so a screen reader reads
# a message as it arrives.
class Views::Conversations::Thread < Views::Base
  def self.dom_id(conversation) = "conversation-#{conversation.id}-messages"

  def initialize(conversation:, messages:, viewer:)
    @conversation = conversation
    @messages = messages
    @viewer = viewer
  end

  def view_template
    div(id: self.class.dom_id(@conversation), class: "conversation__messages", role: "log",
        data: { conversation_target: "thread" }) do
      if @messages.empty?
        render Components::EmptyState.new(icon: "fa-comment-dots", message: t("conversations.show.empty"))
      else
        render Views::Conversations::Bubbles.new(messages: @messages, viewer: @viewer)
      end
    end
  end
end
