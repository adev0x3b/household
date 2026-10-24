# frozen_string_literal: true

# The way back to earlier messages, at the top of the thread: a link that
# fetches the page before `before` (ConversationsController#older) and is
# replaced by the next one, or by nothing to click once the thread's
# beginning is on the page.
class Views::Conversations::Older < Views::Base
  def self.dom_id(conversation) = "conversation-#{conversation.id}-older"

  def initialize(conversation:, before:, more:)
    @conversation = conversation
    @before = before
    @more = more
  end

  def view_template
    if @more
      a(id: self.class.dom_id(@conversation), href: older_conversation_path(@conversation, before: @before), class: "conversation__older",
        data: { turbo_stream: true, action: "click->conversation#loadingOlder" }) { t("conversations.show.older") }
    else
      span(id: self.class.dom_id(@conversation), class: "conversation__older conversation__older--start", hidden: @before.nil?) { t("conversations.show.start") }
    end
  end
end
