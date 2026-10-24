# frozen_string_literal: true

# The analytes lab results are read against, each a card; the search and the
# "new" button are the top bar's.
class Views::Analytes::Index < Views::Base
  def initialize(analytes:, query: nil)
    @analytes = analytes
    @query = query
  end

  def page_title = t("analytes.index.title")

  def navbar_controls
    search = Components::IndexSearch.new(url: routes.analytes_path, results: Views::Analytes::List, query: @query,
                                         placeholder: t("analytes.index.search_placeholder"))
    new_analyte = Components::Action.new(href: routes.new_analyte_path, icon: "fa-plus", label: t("analytes.index.new"), turbo_stream: true)
    Components::PageControls.new(search: search, actions: [ new_analyte ])
  end

  def view_template
    div(class: "analytes") do
      render Components::PageHeader.new(title: t("analytes.index.title"), back_href: home_section_path(section: "healthcare"), back_label: t("home.tabs.healthcare"))
      render Views::Analytes::List.new(analytes: @analytes, query: @query)
    end
  end
end
