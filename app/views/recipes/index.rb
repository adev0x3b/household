# frozen_string_literal: true

# The recipes, each a card; the search and the "new" button are the top bar's.
class Views::Recipes::Index < Views::Base
  def initialize(recipes:, viewer:, query: nil)
    @recipes = recipes
    @viewer = viewer
    @query = query
  end

  def page_title = t("recipes.index.title")

  def navbar_controls
    search = Components::IndexSearch.new(url: routes.recipes_path, results: Views::Recipes::List, query: @query,
                                         placeholder: t("recipes.index.search_placeholder"))
    new_recipe = Components::Action.new(href: routes.new_recipe_path, icon: "fa-plus", label: t("recipes.index.new"), turbo_stream: true)
    Components::PageControls.new(search: search, actions: [ new_recipe ])
  end

  def view_template
    div(class: "recipes") do
      render Components::PageHeader.new(title: t("recipes.index.title"), back_href: home_section_path(section: "pantry"), back_label: t("home.tabs.pantry"))
      render Views::Recipes::List.new(recipes: @recipes, viewer: @viewer, query: @query)
    end
  end
end
