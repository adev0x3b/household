# frozen_string_literal: true

# The healthcare supplies: the index with each one's stock, and the modal
# that adds or edits one (a new supply comes with its first purchase, paid
# for through PurchaseTransactable). A supply's purchases and their
# history are SupplyPurchasesController's.
class SuppliesController < ApplicationController
  include SearchableIndex
  include PurchaseTransactable

  before_action :set_supply, only: [ :edit, :update, :destroy ]

  def index
    @supplies = index_page(policy_scope(Supply).search(search_query).order(:name, :id)).tap do |supplies|
      Supply.preload_stock(supplies.to_a)
      Supply.preload_daily_rates(supplies.to_a)
    end

    render_searchable_index(
      page: Views::Supplies::Index.new(supplies: @supplies, viewer: current_profile, query: search_query),
      results: Views::Supplies::List.new(supplies: @supplies, viewer: current_profile, query: search_query)
    )
  end

  def new
    @supply = current_profile.supplies.new
    @supply.supply_purchases.build
    authorize @supply

    render_modal(form_view(@supply, supplies_path), page: supplies_path)
  end

  def edit
    authorize @supply

    render_modal(form_view(@supply, supply_path(@supply)), page: supplies_path)
  end

  def create
    @supply = build_supply
    authorize @supply

    result = Purchases::Save.call(@supply, cost: transaction_params, category: :healthcare,
                                           paying_for: ->(supply) { supply.supply_purchases.first }) { build_supply }
    if result.success?
      redirect_back_after_save(supplies_path, notice: t("supplies.notices.created"))
    else
      render turbo_stream: redraw_modal(form_view(result.record, supplies_path)), status: :unprocessable_content
    end
  end

  def update
    authorize @supply

    if @supply.update(supply_params)
      redirect_back_after_save(supplies_path, notice: t("supplies.notices.updated"))
    else
      render turbo_stream: redraw_modal(form_view(@supply, supply_path(@supply))), status: :unprocessable_content
    end
  end

  def destroy
    authorize @supply

    if @supply.destroy
      redirect_after_destroy(supply_path(@supply), list: supplies_path, notice: t("supplies.notices.destroyed"))
    else
      refuse(t("supplies.notices.in_use", name: @supply.name))
    end
  end

  private

  def set_supply
    @supply = Supply.accessible_by(current_profile).find(params[:id])
  end

  def build_supply
    supply = current_profile.supplies.new(supply_params)
    supply.supply_purchases.each { |purchase| purchase.profile = current_profile }
    supply
  end

  def supply_params
    params.expect(supply: [
                    :name, :category, :unit_label, :low_stock_threshold, :pao_days,
                    supply_purchases_attributes: [ %i[quantity_purchased purchased_on expires_on opened_on pao_days_override] ]
                  ])
  end

  def form_view(supply, url)
    Views::Supplies::Modals::Form.new(
      supply: supply,
      url: url,
      available_transaction_counterparties: available_transaction_counterparties(current_profile)
    )
  end
end
