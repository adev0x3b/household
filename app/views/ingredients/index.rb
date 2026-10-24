# frozen_string_literal: true

# The pantry's ingredients, each a card; the search and the "new" button are the
# top bar's.
class Views::Ingredients::Index < Views::Base
  def initialize(ingredients:, query: nil)
    @ingredients = ingredients
    @query = query
  end

  def page_title = t("ingredients.index.title")

  def navbar_controls
    search = Components::IndexSearch.new(url: routes.ingredients_path, results: Views::Ingredients::List, query: @query,
                                         placeholder: t("ingredients.index.search_placeholder"))
    new_ingredient = Components::Action.new(href: routes.new_ingredient_path, icon: "fa-plus", label: t("ingredients.index.new"), turbo_stream: true)
    Components::PageControls.new(search: search, actions: [ new_ingredient ])
  end

  def view_template
    div(class: "ingredients") do
      render Components::PageHeader.new(title: t("ingredients.index.title"), back_href: home_section_path(section: "pantry"), back_label: t("home.tabs.pantry"))
      render Views::Ingredients::List.new(ingredients: @ingredients, query: @query)
    end
  end
end
