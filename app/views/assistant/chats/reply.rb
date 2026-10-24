# frozen_string_literal: true

# The assistant's reply while it is being written, with "thinking" dots
# until the first words arrive. A MessageBubble replaces it when done.
#
# In the chat's log, a screen reader hears "thinking" once, then the whole
# answer once it is done. The words in between are drawn again with every
# few that arrive, and are kept out of the log's announcements, which would
# otherwise read the answer from its start each time.
class Views::Assistant::Chats::Reply < Views::Base
  ID = "assistant-reply"
  CLASSES = "assistant-message assistant-message--assistant assistant-message--pending"

  def initialize(text:)
    @text = text
  end

  def view_template
    if @text.present?
      div(id: ID, class: CLASSES, aria: { live: "off" }) do
        render Views::Assistant::Chats::MessageBubble.new(role: "assistant", content: @text)
      end
    else
      div(id: ID, class: CLASSES, role: "status") do
        div(class: "assistant-message__bubble") do
          span(class: "is-sr-only") { t("assistant.thread.thinking") }
          3.times { span(class: "assistant-message__dot", aria: { hidden: "true" }) }
        end
      end
    end
  end
end
