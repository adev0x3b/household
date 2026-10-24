# frozen_string_literal: true

class Views::Ingredients::Card < Views::Base
  def initialize(ingredient:)
    @ingredient = ingredient
  end

  def view_template
    render Components::Card.new(dom_id: "ingredient_#{@ingredient.id}") do |card|
      card.header do
        span(class: "ingredient-card__name") { @ingredient.name }
        span(class: "ingredient-card__category") { render Views::Ingredients::Category.new(category: @ingredient.category, label: false) }
      end
      card.body { quantity_line }
      card.actions { actions }
    end
  end

  private

  def quantity_line
    p(class: "ingredient-card__quantity") { quantity_with_unit(@ingredient.quantity, @ingredient.unit) }
  end

  # Its history and buying on the card; changing it behind "more".
  def actions
    render Components::ItemAction.new(href: ingredient_purchases_path(@ingredient), icon: "fa-clock-rotate-left", label: t("ingredients.card.history"))
    render Components::ItemAction.new(href: new_ingredient_purchase_path(@ingredient), icon: "fa-cart-plus",
                                      label: t("ingredients.card.buy"), turbo_stream: true)
    render Components::ItemMenu.new(label: t("ingredients.card.more"), actions: menu_actions)
  end

  def menu_actions
    [
      Components::Action.new(href: edit_ingredient_path(@ingredient), icon: "fa-pen", label: t("ingredients.card.edit"), turbo_stream: true),
      Components::Action.new(href: ingredient_path(@ingredient), icon: "fa-trash", label: t("ingredients.card.destroy"),
                             method: :delete, confirm: t("ingredients.confirm_destroy"), danger: true)
    ]
  end
end
