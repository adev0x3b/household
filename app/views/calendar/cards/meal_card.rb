# frozen_string_literal: true

# A meal's day: home-cooked (its recipes, and a warning when the pantry
# can't cover them yet), eaten out or ordered in (with its bill inside).
class Views::Calendar::Cards::MealCard < Views::Calendar::Cards::Base
  KIND_ICONS = {
    "home" => "fa-utensils",
    "eating_out" => "fa-store",
    "ordered_in" => "fa-bag-shopping"
  }.freeze

  def self.icon = "fa-utensils"

  private

  def prefix = "meal-card"

  def kind = details.kind.presence || "home"
  def home? = kind == "home"
  def recipes = details.resolved_recipes

  def content
    div(class: "meal-card__content") do
      div(class: "meal-card__header") do
        render Components::Icon.new(KIND_ICONS.fetch(kind), class: "meal-card__kind-icon")
        title_link
        low_stock_icon if @event.short_on?(@occurrence)
      end

      detail_row
      outcome
      attached_costs
    end
  end

  def low_stock_icon
    render Components::Icon.new(
      "fa-triangle-exclamation", label: t("meals.low_stock_warning"), class: "meal-card__low-stock-icon"
    )
  end

  def meal_type_label
    meal_type = details.meal_type
    t("meals.meal_type.#{meal_type}") if meal_type
  end

  # The title already lists the recipes when none was typed; only spell them
  # out when a custom title hides them.
  def recipe_names
    return [] unless home? && @occurrence.title.present?

    recipes.map(&:name)
  end

  def away_label
    t("meals.kind.#{kind}") unless home?
  end

  def detail_row
    parts = [ meal_type_label, away_label, recipe_names.to_sentence.presence ].compact_blank
    return if parts.empty?

    span(class: "meal-card__detail") { parts.join(" · ") }
  end
end
