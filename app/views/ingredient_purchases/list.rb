# frozen_string_literal: true

# An ingredient's purchases, a page at a time, each row with its own edit
# and delete (IngredientPurchasesController). The frame the top bar's search
# and the page links reload, so the search box is never drawn again.
class Views::IngredientPurchases::List < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "ingredient_history_results"

  def initialize(ingredient:, purchases:)
    @ingredient = ingredient
    @purchases = purchases
  end

  def view_template
    turbo_frame_tag(FRAME_ID, class: "ingredient-history__results") { results }
  end

  private

  def results
    if @purchases.any?
      div(class: "ingredient-history__list") { @purchases.each { |purchase| purchase_row(purchase) } }
      render Components::Pagination.new(collection: @purchases, turbo_frame: FRAME_ID, turbo_action: "advance")
    else
      render Components::EmptyState.new(icon: "fa-clock-rotate-left", message: t("ingredients.history.empty"))
    end
  end

  def purchase_row(purchase)
    div(class: "ingredient-purchase-row") do
      div(class: "ingredient-purchase-row__main") do
        span(class: "ingredient-purchase-row__quantity") { quantity_with_unit(purchase.quantity, purchase.unit) }
        span(class: "ingredient-purchase-row__date") { where_and_when(purchase) }
      end

      div(class: "ingredient-purchase-row__actions") do
        cost(purchase)
        render Components::ItemAction.new(href: edit_ingredient_purchase_path(purchase), icon: "fa-pen",
                                          label: t("ingredient_purchases.form.edit"), turbo_stream: true)
        render Components::ItemAction.new(href: ingredient_purchase_path(purchase), icon: "fa-trash",
                                          label: t("ingredient_purchases.form.destroy"), method: :delete,
                                          confirm: t("ingredient_purchases.confirm_destroy"), danger: true)
      end
    end
  end

  # The day and the shop: everything the search matches on.
  def where_and_when(purchase)
    [ l(purchase.purchased_on, format: :long), purchase.cost&.details&.counterparty.presence ].compact.join(" · ")
  end

  # Read only: a purchase's cost is changed in its own form.
  def cost(purchase)
    cost = purchase.cost
    return unless cost

    span(class: "ingredient-purchase-row__cost-label", title: t("ingredient_purchases.form.cost_section.label")) do
      render Components::Icon.new("fa-receipt")
      whitespace
      plain Reports::Money.new(cents: cost.details.amount_cents, currency: cost.details.currency).to_s
    end
  end
end
