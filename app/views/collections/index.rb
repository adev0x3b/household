# frozen_string_literal: true

# A section's collections (Healthcare's therapies), each a card; the search
# and the "new" button are the top bar's, worded for the section.
class Views::Collections::Index < Views::Base
  def initialize(collections:, section:, viewer:, query: nil)
    @collections = collections
    @section = section
    @viewer = viewer
    @query = query
  end

  def page_title = t("collections.sections.#{@section}.index.title")

  # The section travels with the search and the "new" button, so what is
  # found and what is made stays in it.
  def navbar_controls
    search = Components::IndexSearch.new(url: routes.collections_path(section: @section), results: Views::Collections::List, query: @query,
                                         placeholder: t("collections.sections.#{@section}.index.search_placeholder"), hidden: { section: @section })
    new_collection = Components::Action.new(href: routes.new_collection_path(section: @section), icon: "fa-plus",
                                            label: t("collections.sections.#{@section}.index.new"), turbo_stream: true)
    Components::PageControls.new(search: search, actions: [ new_collection ])
  end

  def view_template
    div(class: "collections section--#{@section}") do
      render Components::PageHeader.new(title: t("collections.sections.#{@section}.index.title"),
                                        back_href: home_section_path(section: @section), back_label: t("home.tabs.#{@section}"))
      render Views::Collections::List.new(collections: @collections, section: @section, viewer: @viewer, query: @query)
    end
  end
end
