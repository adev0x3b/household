# frozen_string_literal: true

# Shared by SuppliesController (the optional first purchase of a new
# supply), SupplyPurchasesController (a restock) and
# IngredientPurchasesController: the cost section of their forms — three
# fields (amount, who was paid, payment method) under `transaction[…]`,
# which Purchases::Save turns into the one expense about the purchase.
module PurchaseTransactable
  extend ActiveSupport::Concern

  private

  def transaction_params
    params.fetch(:transaction, {}).permit(
      :amount, :counterparty_mode, :counterparty, :counterparty_profile_id, :payment_method
    )
  end

  def available_transaction_counterparties(profile)
    profile.housemates.order(:username)
  end
end
