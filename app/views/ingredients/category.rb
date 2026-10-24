# frozen_string_literal: true

# The store section an ingredient is found in (Ingredient#category): its icon
# in the section color, with the name next to it, or the name as a tooltip
# when there's no room (`label: false`).
#
#   render Views::Ingredients::Category.new(category: ingredient.category)
#   render Views::Ingredients::Category.new(category: ingredient.category, label: false)
class Views::Ingredients::Category < Views::Base
  ICONS = {
    "produce" => "fa-carrot", "dairy_eggs" => "fa-egg", "meat_fish" => "fa-fish", "bakery" => "fa-bread-slice",
    "pantry" => "fa-jar", "frozen_foods" => "fa-snowflake", "drinks" => "fa-bottle-water", "household" => "fa-pump-soap",
    "other" => "fa-basket-shopping"
  }.freeze

  def initialize(category:, label: true)
    @category = ICONS.key?(category.to_s) ? category.to_s : "other"
    @label = label
  end

  def view_template
    name = t("ingredients.category.#{@category}")

    span(class: "ingredient-category") do
      render Components::Icon.new(ICONS.fetch(@category), label: (name unless @label), class: "ingredient-category__icon")
      span(class: "ingredient-category__label") { name } if @label
    end
  end
end
