# frozen_string_literal: true

# A supply's purchases, a page of them at a time, each corrected or deleted
# on its row. A page rather than a modal, so correcting a purchase opens its
# form over the history instead of on top of another modal.
class Views::SupplyPurchases::Index < Views::Base
  def initialize(supply:, purchases:, query:)
    @supply = supply
    @purchases = purchases
    @query = query
  end

  def page_title = t("supplies.history.title", name: @supply.name)

  def navbar_controls
    search = Components::IndexSearch.new(url: routes.supply_purchases_path(@supply), results: Views::SupplyPurchases::List, query: @query,
                                         placeholder: t("supplies.history.search_placeholder"))
    buy = Components::Action.new(href: routes.new_supply_purchase_path(@supply), icon: "fa-plus",
                                 label: t("supplies.card.buy_more"), turbo_stream: true)
    Components::PageControls.new(search: search, actions: [ buy ])
  end

  def view_template
    div(class: "supply-history") do
      a(href: supplies_path, class: "supply-history__back") do
        render Components::Icon.new("fa-arrow-left")
        span { t("supplies.history.back") }
      end
      h1(class: "page-title supply-history__title") { page_title }
      render Views::SupplyPurchases::List.new(supply: @supply, purchases: @purchases)
    end
  end
end
