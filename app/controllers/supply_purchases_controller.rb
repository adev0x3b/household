# frozen_string_literal: true

# A supply's purchases (restocks): its history page, searched from the top
# bar; the modal that records or corrects one, with its cost
# (PurchaseTransactable), for a collection the person can reach or none;
# and deleting one. A purchase is made under its supply and is then its
# own record. Each change goes back to the page it was made on, which
# Turbo refreshes in place: the supply's stock and its history both change.
class SupplyPurchasesController < ApplicationController
  include SearchableIndex
  include PurchaseTransactable
  include KeepsWhatWasTyped

  before_action :set_supply, only: %i[index new create]
  before_action :set_supply_purchase, only: %i[edit update destroy]

  def index
    authorize @supply, :show?

    query = Supplies::PurchaseHistoryQuery.new(scope: SupplyPurchase.accessible_by(current_profile).where(supply: @supply),
                                               filters: { q: search_query })
    purchases = query.call.paginate(page: params[:page], per_page: Supplies::PurchaseHistoryQuery::PAGE_SIZE)
    Costable.preload_cost(purchases.to_a)

    render_searchable_index(page: Views::SupplyPurchases::Index.new(supply: @supply, purchases: purchases, query: search_query),
                            results: Views::SupplyPurchases::List.new(supply: @supply, purchases: purchases))
  end

  def new
    @supply_purchase = @supply.supply_purchases.build(purchased_on: Date.current)
    authorize @supply_purchase

    render_modal(form_view(@supply_purchase, supply_purchases_path(@supply)), page: supply_purchases_path(@supply))
  end

  def edit
    authorize @supply_purchase

    render_modal(form_view(@supply_purchase, supply_purchase_path(@supply_purchase)), page: supply_purchases_path(@supply_purchase.supply))
  end

  def create
    @supply_purchase = build_supply_purchase
    authorize @supply_purchase

    result = Purchases::Save.call(@supply_purchase, cost: transaction_params, category: :healthcare) { build_supply_purchase }
    if result.success?
      redirect_back_after_save(supply_purchases_path(@supply), notice: t("supply_purchases.notices.created"))
    else
      render turbo_stream: redraw_modal(form_view(result.record, supply_purchases_path(@supply))), status: :unprocessable_content
    end
  end

  def update
    authorize @supply_purchase

    @supply_purchase.collection_id = resolve_collection_id(supply_purchase_params[:collection_id])
    typed = typed_fields(@supply_purchase, supply_purchase_params.merge(collection_id: @supply_purchase.collection_id))

    saved = @supply_purchase.edit_as(current_profile, typed:) do
      Purchases::Save.call(@supply_purchase, attributes: supply_purchase_params.except(:collection_id),
                                             cost: transaction_params, category: :healthcare).success?
    end
    if saved
      redirect_back_after_save(supply_purchases_path(@supply_purchase.supply), notice: t("supply_purchases.notices.updated"))
    else
      render turbo_stream: redraw_modal(form_view(@supply_purchase, supply_purchase_path(@supply_purchase))), status: :unprocessable_content
    end
  end

  def destroy
    authorize @supply_purchase
    @supply_purchase.destroy!

    redirect_after_destroy(supply_purchase_path(@supply_purchase),
                           list: supply_purchases_path(@supply_purchase.supply),
                           notice: t("supply_purchases.notices.destroyed"))
  end

  private

  def set_supply
    @supply = Supply.accessible_by(current_profile).find(params[:supply_id])
  end

  def set_supply_purchase
    @supply_purchase = SupplyPurchase.accessible_by(current_profile).find(params[:id])
  end

  # The supply is the route's, never the form's; a purchase never moves to another.
  def build_supply_purchase
    purchase = @supply.supply_purchases.build(supply_purchase_params)
    purchase.profile = current_profile
    purchase.collection_id = resolve_collection_id(supply_purchase_params[:collection_id])
    purchase
  end

  def supply_purchase_params
    params.expect(supply_purchase: %i[collection_id quantity_purchased quantity_remaining purchased_on expires_on opened_on pao_days_override lock_version])
  end

  # Only a collection the person can reach — never trust the picker's id.
  def resolve_collection_id(id)
    return nil if id.blank?

    Collection.accessible_by(current_profile).where(id: id).pick(:id)
  end

  def form_view(supply_purchase, url)
    Views::SupplyPurchases::Modals::Form.new(
      supply_purchase: supply_purchase,
      url: url,
      current_profile: current_profile,
      available_transaction_counterparties: available_transaction_counterparties(current_profile)
    )
  end
end
