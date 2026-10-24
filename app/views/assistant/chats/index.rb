# frozen_string_literal: true

# The assistant's chats, newest first. The "new" button is a POST
# because it saves a blank chat.
class Views::Assistant::Chats::Index < Views::Base
  def initialize(chats:, query: nil)
    @chats = chats
    @query = query
  end

  def page_title = t("assistant.chats.title")

  def navbar_controls
    search = Components::IndexSearch.new(url: routes.assistant_chats_path, results: Views::Assistant::Chats::List, query: @query,
                                         placeholder: t("assistant.chats.search_placeholder"))
    new_chat = Components::Action.new(href: routes.assistant_chats_path, icon: "fa-plus", label: t("assistant.chats.new"), method: :post)
    Components::PageControls.new(search: search, actions: [ new_chat ])
  end

  def view_template
    div(class: "assistant assistant--list") do
      div(class: "assistant__header") do
        render Components::PageHeader.new(title: t("assistant.chats.title"))
      end

      render Views::Assistant::Chats::List.new(chats: @chats, query: @query)
    end
  end
end
