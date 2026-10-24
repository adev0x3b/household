# frozen_string_literal: true

# An ingredient's purchases, a page of them at a time, each corrected or
# deleted on its row. A page rather than a modal, so correcting a purchase
# opens its form over the history instead of on top of another modal.
class Views::IngredientPurchases::Index < Views::Base
  def initialize(ingredient:, purchases:, query:)
    @ingredient = ingredient
    @purchases = purchases
    @query = query
  end

  def page_title = t("ingredients.history.title", name: @ingredient.name)

  def navbar_controls
    search = Components::IndexSearch.new(url: routes.ingredient_purchases_path(@ingredient), results: Views::IngredientPurchases::List,
                                         query: @query, placeholder: t("ingredients.history.search_placeholder"))
    buy = Components::Action.new(href: routes.new_ingredient_purchase_path(@ingredient), icon: "fa-cart-plus",
                                 label: t("ingredients.card.buy"), turbo_stream: true)
    Components::PageControls.new(search: search, actions: [ buy ])
  end

  def view_template
    div(class: "ingredient-history") do
      a(href: ingredients_path, class: "ingredient-history__back") do
        render Components::Icon.new("fa-arrow-left")
        span { t("ingredients.history.back") }
      end
      h1(class: "page-title ingredient-history__title") { page_title }
      render Views::IngredientPurchases::List.new(ingredient: @ingredient, purchases: @purchases)
    end
  end
end
