# frozen_string_literal: true

# One conversation: its header, the thread (with the way back to earlier
# messages, and who has seen the newest), and the composer. Full height
# on a phone, like the assistant's chat. Everyone in it gets each change
# pushed over their own signed stream (Conversations::Broadcaster), so the
# page is opened with `turbo_stream_from conversation, viewer`; DOM ids
# are shared with the broadcaster. The quick emoji every message's smile
# opens is drawn once, after the composer. Renaming the household's
# conversation is the top bar's.
class Views::Conversations::Show < Views::Base
  include Phlex::Rails::Helpers::TurboStreamFrom

  # readers: who the line under the newest message names (Conversations::Readers).
  def initialize(conversation:, messages:, more:, readers:, viewer:)
    @conversation = conversation
    @messages = messages
    @more = more
    @readers = readers
    @viewer = viewer
  end

  def page_title = @conversation.title_for(@viewer)

  def navbar_controls
    return unless Pundit.policy!(@viewer, @conversation).update?

    rename = Components::Action.new(href: routes.edit_conversation_path(@conversation), icon: "fa-pen",
                                    label: t("conversations.show.rename"), turbo_stream: true)
    Components::PageControls.new(actions: [ rename ])
  end

  def view_template
    div(class: "conversation section--messages",
        data: { controller: "conversation reaction-picker", conversation_read_url_value: conversation_read_receipt_path(@conversation) }) do
      turbo_stream_from @conversation, @viewer
      render Views::Conversations::Header.new(conversation: @conversation, viewer: @viewer)

      div(class: "conversation__scroll", data: { conversation_target: "scroll" }) do
        render Views::Conversations::Older.new(conversation: @conversation, before: @messages.first&.id, more: @more)
        render Views::Conversations::Thread.new(conversation: @conversation, messages: @messages, viewer: @viewer)
        render Views::Conversations::Seen.new(conversation: @conversation, readers: @readers)
      end

      render Views::Conversations::Composer.new(conversation: @conversation, viewer: @viewer)
      render Views::Conversations::ReactionPicker.new
    end
  end
end
