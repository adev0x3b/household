# frozen_string_literal: true

module GroceryLists
  # A list's items in the order they are shopped: what is still to buy by
  # store section, in the order of a walk through the shop and by name within
  # each section, then what is already in the basket, the last one picked up
  # first. Sorted in memory, from the items the list has loaded.
  class Aisles
    Aisle = Data.define(:category, :items)

    def initialize(items)
      @items = items
    end

    def empty? = @items.empty?

    def to_buy
      @items.reject(&:checked?).group_by { |item| item.category.to_s }
        .sort_by { |category, _| position(category) }
        .map do |category, items|
          Aisle.new(category: category, items: items.sort_by { |item| item.ingredient.name.downcase })
        end
    end

    # The id breaks a tie between two items ticked in the same second.
    def in_basket = @items.select(&:checked?).sort_by { |item| [ item.checked_at || Time.zone.at(0), item.id ] }.reverse

    private

    # A section the walk doesn't name comes last.
    def position(category) = Ingredient::CATEGORY_ORDER.index(category) || Ingredient::CATEGORY_ORDER.size
  end
end
