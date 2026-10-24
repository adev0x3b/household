# frozen_string_literal: true

# The quick emoji every message's smile opens on a conversation's page,
# drawn once for the page (Views::Conversations::Show) rather than once a
# message, and pointed by reaction_picker_controller.js at the message
# pressed. Each emoji gives that reaction, as the chips under a message do.
class Views::Conversations::ReactionPicker < Views::Base
  ID = "reaction_picker"

  # What a message's smile tells the picker: where its reactions are given,
  # the message it opens over (by its id), and which of the message's edges
  # it opens from: its own side of the thread, so it never runs off the
  # screen.
  def self.opener_data(url:, message_id:, mine:)
    { action: "reaction-picker#open", reaction_picker_url_param: url, reaction_picker_message_param: message_id,
      reaction_picker_align_param: mine ? "end" : "start" }
  end

  def view_template
    # Drawn at the page's end, far from the message pressed, so it names itself
    div(id: ID, class: "reaction-picker", role: "group", aria: { label: t("conversations.reactions.add") },
        data: { reaction_picker_target: "menu",
                action: "turbo:before-morph-element->reaction-picker#holdWhileOpen" }) do
      form(method: "post", class: "reaction-picker__form",
           data: { reaction_picker_target: "form", action: "submit->reaction-picker#chosen" }) do
        MessageReaction::QUICK.each do |emoji|
          button(type: "submit", name: "emoji", value: emoji, class: "reaction-picker__emoji",
                 aria: { label: t("conversations.reactions.react_with", emoji: emoji) }) { emoji }
        end
      end
    end
  end
end
