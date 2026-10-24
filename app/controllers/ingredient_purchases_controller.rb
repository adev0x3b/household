# frozen_string_literal: true

# A pantry ingredient's purchases: its history page, searched from the top
# bar; the modal that records or corrects one, with its cost
# (PurchaseTransactable); and deleting one. A purchase is made under its
# ingredient and is then its own record. Each change goes back to the page
# it was made on, which Turbo refreshes in place: the ingredient's stock
# and its history both change.
class IngredientPurchasesController < ApplicationController
  include SearchableIndex
  include PurchaseTransactable

  before_action :set_ingredient, only: %i[index new create]
  before_action :set_ingredient_purchase, only: %i[edit update destroy]

  def index
    authorize @ingredient, :show?

    query = Ingredients::PurchaseHistoryQuery.new(scope: IngredientPurchase.accessible_by(current_profile).where(ingredient: @ingredient),
                                                  filters: { q: search_query })
    purchases = query.call.paginate(page: params[:page], per_page: Ingredients::PurchaseHistoryQuery::PAGE_SIZE)
    Costable.preload_cost(purchases.to_a)

    render_searchable_index(page: Views::IngredientPurchases::Index.new(ingredient: @ingredient, purchases: purchases, query: search_query),
                            results: Views::IngredientPurchases::List.new(ingredient: @ingredient, purchases: purchases))
  end

  def new
    @ingredient_purchase = build_purchase(purchased_on: Date.current)
    authorize @ingredient_purchase

    render_modal(form_view(@ingredient_purchase, ingredient_purchases_path(@ingredient)), page: ingredient_purchases_path(@ingredient))
  end

  def edit
    authorize @ingredient_purchase

    render_modal(form_view(@ingredient_purchase, ingredient_purchase_path(@ingredient_purchase)),
                 page: ingredient_purchases_path(@ingredient_purchase.ingredient))
  end

  def create
    @ingredient_purchase = build_purchase(ingredient_purchase_params)
    authorize @ingredient_purchase

    result = Purchases::Save.call(@ingredient_purchase, cost: transaction_params, category: :groceries) { build_purchase(ingredient_purchase_params) }
    if result.success?
      redirect_back_after_save(ingredient_purchases_path(@ingredient), notice: t("ingredient_purchases.notices.created"))
    else
      render turbo_stream: redraw_modal(form_view(result.record, ingredient_purchases_path(@ingredient))), status: :unprocessable_content
    end
  end

  def update
    authorize @ingredient_purchase

    result = Purchases::Save.call(@ingredient_purchase, attributes: ingredient_purchase_params.except(:unit_name),
                                                        cost: transaction_params, category: :groceries)
    if result.success?
      redirect_back_after_save(ingredient_purchases_path(@ingredient_purchase.ingredient), notice: t("ingredient_purchases.notices.updated"))
    else
      render turbo_stream: redraw_modal(form_view(result.record, ingredient_purchase_path(@ingredient_purchase))), status: :unprocessable_content
    end
  end

  def destroy
    authorize @ingredient_purchase
    @ingredient_purchase.destroy!

    redirect_after_destroy(ingredient_purchase_path(@ingredient_purchase),
                           list: ingredient_purchases_path(@ingredient_purchase.ingredient),
                           notice: t("ingredient_purchases.notices.destroyed"))
  end

  private

  def set_ingredient
    @ingredient = current_profile.ingredients.find(params[:ingredient_id])
  end

  def set_ingredient_purchase
    @ingredient_purchase = IngredientPurchase.accessible_by(current_profile).find(params[:id])
  end

  # The ingredient is the route's, never the form's; a purchase never moves to another.
  def build_purchase(attributes)
    purchase = @ingredient.ingredient_purchases.build(attributes)
    purchase.profile = current_profile
    purchase
  end

  def ingredient_purchase_params
    params.expect(ingredient_purchase: %i[quantity unit_name purchased_on])
  end

  def form_view(purchase, url)
    Views::IngredientPurchases::Modals::Form.new(
      ingredient_purchase: purchase,
      url: url,
      available_transaction_counterparties: available_transaction_counterparties(current_profile)
    )
  end
end
