# frozen_string_literal: true

# The chats results frame: the index page renders it, and so does
# the navbar search on its own (Components::IndexSearch).
class Views::Assistant::Chats::List < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "assistant_chats_results"

  def initialize(chats:, query: nil)
    @chats = chats
    @query = query
  end

  def view_template
    # A chat opens as a whole page, not inside the frame.
    turbo_frame_tag(FRAME_ID, class: "index-results", target: "_top") do
      if @chats.empty?
        render Components::EmptyState.new(icon: "fa-feather-pointed", message: t(@query.present? ? "assistant.chats.empty_search" : "assistant.chats.empty"))
      else
        ul(class: "assistant__chats") do
          @chats.each do |chat|
            li(class: "assistant__chat") do
              a(href: assistant_chat_path(chat), class: "assistant__chat-link") do
                span(class: "assistant__chat-title") { chat.title.presence || t("assistant.chats.new_title") }
                span(class: "assistant__chat-date") { l(chat.updated_at, format: :short) }
              end
              chat_actions(chat)
            end
          end
        end
      end
      render Components::Pagination.new(collection: @chats, turbo_frame: FRAME_ID, turbo_action: "advance")
    end
  end

  private

  def chat_actions(chat)
    title = chat.title.presence || t("assistant.chats.new_title")

    div(class: "assistant__chat-actions") do
      render Components::ItemAction.new(href: edit_assistant_chat_path(chat), icon: "fa-pen", label: t("assistant.chats.rename"), turbo_stream: true)
      render Components::ItemAction.new(href: assistant_chat_path(chat), icon: "fa-trash", label: t("assistant.chats.delete"), method: :delete,
                                        confirm: t("assistant.chats.confirm_destroy", title: title), danger: true)
    end
  end
end
