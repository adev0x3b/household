# frozen_string_literal: true

# The list's items: what is still to buy, grouped by store section in the
# order of a walk through the shop, then what is already in the basket,
# folded away at the bottom. When everything is in the basket, the way to
# finish the shop appears here, so it shows up the moment the last item is
# ticked, on this page and on a housemate's. Replaced as one unit by every
# change (GroceryListStreams, GroceryLists::Broadcaster).
class Views::GroceryLists::Items < Views::Base
  include Phlex::Rails::Helpers::ButtonTo

  def self.dom_id(grocery_list) = "grocery_list-#{grocery_list.id}-items"
  FINISH_ID = "grocery-list-finish"

  def initialize(grocery_list:)
    @grocery_list = grocery_list
  end

  def view_template
    div(id: self.class.dom_id(@grocery_list), class: "grocery-list-items") do
      if aisles.empty?
        render Components::EmptyState.new(icon: "fa-basket-shopping", message: t("grocery_lists.show.items_empty"))
      else
        aisles.to_buy.each { |aisle| group(aisle) }
        finish if @grocery_list.all_bought? && @grocery_list.active?
        basket if in_basket.any?
      end
    end
  end

  private

  def aisles = @aisles ||= @grocery_list.aisles

  def in_basket = @in_basket ||= aisles.in_basket

  # What is still to buy, in the order of the walk, across the sections.
  def walk = @walk ||= aisles.to_buy.flat_map(&:items)

  # Ticked or removed, a row leaves its section, so the focus goes to the
  # next item to buy, else the one before; the last one ticked brings the
  # way to finish the shop, which takes it.
  def focus_fallback(item)
    at = walk.index(item)
    after = walk[at + 1]
    before = walk[at - 1] if at.positive?
    [ after, before ].compact.map { Views::GroceryListItems::Row.check_id(_1) }.push(FINISH_ID).join(" ")
  end

  def group(aisle)
    section(class: "grocery-list-group") do
      h2(class: "grocery-list-group__title") do
        render Views::Ingredients::Category.new(category: aisle.category)
        span(class: "grocery-list-group__count") { aisle.items.size }
      end
      ul(class: "grocery-list-group__rows") do
        aisle.items.each { |item| render Views::GroceryListItems::Row.new(item: item, focus_fallback: focus_fallback(item)) }
      end
    end
  end

  def finish
    div(class: "grocery-list-finish", role: "status") do
      p(class: "grocery-list-finish__text") do
        render Components::Icon.new("fa-circle-check")
        span { t("grocery_lists.show.all_bought") }
      end
      button_to(t("grocery_lists.show.finish_cta"), grocery_list_completion_path(@grocery_list), method: :post, class: "button is-primary", id: FINISH_ID)
    end
  end

  def basket
    render Components::Disclosure.new(key: "grocery-list-#{@grocery_list.id}-basket",
                                      title: t("grocery_lists.show.basket_title", count: in_basket.size), open: false) do
      ul(class: "grocery-list-basket__rows") { in_basket.each { |item| render Views::GroceryListItems::Row.new(item: item) } }
    end
  end
end
