# frozen_string_literal: true

# Under the newest message: who has read it, among the others (never its
# sender, never the viewer). "Seen" in a direct conversation, "Seen by
# Sam, Robin" in the household's. Replaced as people read
# (Conversations::Broadcaster.read); empty when there's nothing to say.
class Views::Conversations::Seen < Views::Base
  def self.dom_id(conversation) = "conversation-#{conversation.id}-seen"

  # readers: the people the line names (Conversations::Readers#excluding the viewer).
  def initialize(conversation:, readers:)
    @conversation = conversation
    @readers = readers
  end

  def view_template
    p(id: self.class.dom_id(@conversation), class: "conversation__seen", hidden: @readers.empty?) do
      if @readers.any?
        render Components::Icon.new("fa-check-double")
        plain " "
        plain @conversation.direct? ? t("conversations.show.seen") : t("conversations.show.seen_by", names: @readers.map(&:display_name).to_sentence)
      end
    end
  end
end
