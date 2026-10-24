# frozen_string_literal: true

# The healthcare supplies, each a card with its stock; the search and the
# "add" button are the top bar's.
class Views::Supplies::Index < Views::Base
  def initialize(supplies:, viewer:, query: nil)
    @supplies = supplies
    @viewer = viewer
    @query = query
  end

  def page_title = t("supplies.index.title")

  def navbar_controls
    search = Components::IndexSearch.new(url: routes.supplies_path, results: Views::Supplies::List, query: @query,
                                         placeholder: t("supplies.index.search_placeholder"))
    new_supply = Components::Action.new(href: routes.new_supply_path, icon: "fa-plus", label: t("supplies.index.new"), turbo_stream: true)
    Components::PageControls.new(search: search, actions: [ new_supply ])
  end

  def view_template
    div(class: "supplies") do
      render Components::PageHeader.new(title: t("supplies.index.title"), back_href: home_section_path(section: "healthcare"), back_label: t("home.tabs.healthcare"))
      render Views::Supplies::List.new(supplies: @supplies, viewer: @viewer, query: @query)
    end
  end
end
