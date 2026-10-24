# frozen_string_literal: true

# One line of the list: a conversation (its title, the last thing said,
# when, and how much of it is unread), or a housemate not yet written to.
class Views::Conversations::Row < Views::Base
  include Phlex::Rails::Helpers::ButtonTo

  def self.dom_id(conversation) = "conversation-row-#{conversation.id}"

  # summaries: a Conversations::Summaries read once for many rows, the
  # list's or a push's for everyone in the conversation; a housemate's row
  # has none.
  def initialize(viewer:, conversation: nil, housemate: nil, summaries: nil)
    @viewer = viewer
    @conversation = conversation
    @housemate = housemate
    @summaries = summaries
  end

  def view_template
    @conversation ? conversation_row : housemate_row
  end

  private

  def conversation_row
    last = @summaries.last_message(@conversation)
    unread = @summaries.unread(@conversation, @viewer)

    a(id: self.class.dom_id(@conversation), href: conversation_path(@conversation),
      class: [ "conversation-row", ("conversation-row--unread" if unread.positive?) ]) do
      icon(@conversation.household? ? "fa-people-roof" : "fa-user")
      div(class: "conversation-row__body") do
        p(class: "conversation-row__title") { @conversation.title_for(@viewer) }
        p(class: "conversation-row__preview") { last ? preview(last) : t("conversations.index.nothing_yet") }
      end
      div(class: "conversation-row__meta") do
        time_ago(last.created_at) if last
        span(class: "conversation-row__unread", aria: { label: t("conversations.index.unread", count: unread) }) { unread.to_s } if unread.positive?
      end
    end
  end

  def housemate_row
    button_to(conversations_path, params: { profile_id: @housemate.id }, id: "conversation-row-profile-#{@housemate.id}",
                                  class: "conversation-row conversation-row--start", form: { class: "conversation-row__form" }) do
      icon("fa-user")
      span(class: "conversation-row__body") do
        span(class: "conversation-row__title") { @housemate.display_name }
        span(class: "conversation-row__preview") { t("conversations.index.say_hello") }
      end
    end
  end

  def icon(name)
    span(class: "conversation-row__icon") { render Components::Icon.new(name) }
  end

  # "Sam: see you at 8" — or just the words when they're the viewer's own.
  def preview(message)
    name = message.sender_id == @viewer.id ? t("conversations.index.you") : message.sender.display_name
    message.line(name: name)
  end

  def time_ago(at)
    at = at.in_time_zone # the zone in scope: whoever this row is for
    span(class: "conversation-row__time") { at.today? ? l(at, format: t("time.formats.hour_minute")) : l(at.to_date, format: :short) }
  end
end
