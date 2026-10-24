# frozen_string_literal: true

# The grocery lists, each a card; the search and the "new" button are the
# top bar's.
class Views::GroceryLists::Index < Views::Base
  def initialize(shopping:, finished:, viewer:, query: nil)
    @shopping = shopping
    @finished = finished
    @viewer = viewer
    @query = query
  end

  def page_title = t("grocery_lists.index.title")

  def navbar_controls
    search = Components::IndexSearch.new(url: routes.grocery_lists_path, results: Views::GroceryLists::List, query: @query,
                                         placeholder: t("grocery_lists.index.search_placeholder"))
    new_list = Components::Action.new(href: routes.new_grocery_list_path, icon: "fa-plus", label: t("grocery_lists.index.new"), turbo_stream: true)
    Components::PageControls.new(search: search, actions: [ new_list ])
  end

  def view_template
    div(class: "grocery-lists") do
      render Components::PageHeader.new(title: t("grocery_lists.index.title"), back_href: home_section_path(section: "pantry"), back_label: t("home.tabs.pantry"))
      render Views::GroceryLists::List.new(shopping: @shopping, finished: @finished, viewer: @viewer, query: @query)
    end
  end
end
