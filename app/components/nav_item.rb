# frozen_string_literal: true

# A place to go: a page in the navigation, a tab of an area's pages, a
# pill of a filter. `key:` names it for the tab or pill that is current.
# `pages:` is where its pages live when not under its own path (/assistant
# opens a chat, under /assistant/chats). `section:` gives its icon the
# section's colour. `count:` is how many a filter's pill holds; `badge:` a
# count the navigation draws after its words (Components::CountBadge).
#
#   Components::NavItem.new(href: books_path(status: "read"), label: t("books.status.read"), key: "read", count: 12)
Components::NavItem = Data.define(:href, :label, :icon, :key, :pages, :section, :count, :badge) do
  def initialize(href:, label:, icon: nil, key: nil, pages: nil, section: nil, count: nil, badge: nil)
    super
  end
end
