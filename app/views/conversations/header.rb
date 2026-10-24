# frozen_string_literal: true

# The conversation's top: its title, the way back, and who's in it.
# Replaced for everyone when the household's conversation is renamed.
class Views::Conversations::Header < Views::Base
  def self.dom_id(conversation) = "conversation-#{conversation.id}-header"

  def initialize(conversation:, viewer:)
    @conversation = conversation
    @viewer = viewer
  end

  def view_template
    div(id: self.class.dom_id(@conversation), class: "conversation__header") do
      render Components::PageHeader.new(title: @conversation.title_for(@viewer), subtitle: subtitle,
                                        back_href: conversations_path, back_label: t("conversations.show.back"))
    end
  end

  private

  def subtitle
    if @conversation.household?
      @conversation.participants.map(&:display_name).sort.join(", ")
    else
      t("conversations.show.direct_hint")
    end
  end
end
