# frozen_string_literal: true

# The reactions under a message: "👍 2" chips, highlighted when the viewer
# is among them. Each chip is a toggle button, pressed when the reaction is
# the viewer's, so a tap gives it or takes it back. It carries no token of
# its own, since it is also rendered for the live broadcast, and Turbo sends
# the page's. The region is always rendered, empty when there are none, so
# a reaction can be pushed as an `update` of this region alone
# (Conversations::Broadcaster.reactions_changed) and the bubble above,
# pictures included, stays as it is.
class Views::Conversations::Reactions < Views::Base
  include Phlex::Rails::Helpers::ButtonTo

  def self.dom_id(message) = "message_#{message.id}_reactions"

  def initialize(message:, viewer:)
    @message = message
    @viewer = viewer
  end

  def view_template
    div(id: self.class.dom_id(@message), class: "message__reactions") do
      @message.reactions_by_emoji.each do |emoji, people|
        mine = people.any? { |person| person.id == @viewer.id }
        names = people.map(&:display_name).to_sentence
        button_to(message_reaction_path(@message, emoji: emoji), method: (mine ? :delete : :post), authenticity_token: false,
                                                                 class: [ "message__reaction", ("message__reaction--mine" if mine) ].compact.join(" "), title: names,
                                                                 aria: { pressed: mine.to_s }, form_class: "message__reaction-form", form: { data: { turbo_stream: true } }) do
          span(class: "message__reaction-emoji") { emoji }
          span(class: "message__reaction-count") { people.size.to_s }
          span(class: "is-sr-only") { t("conversations.reactions.by", names: names) }
        end
      end
    end
  end
end
