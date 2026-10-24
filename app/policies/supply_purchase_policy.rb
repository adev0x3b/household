# frozen_string_literal: true

# A supply's purchase is its buyer's. One bought for a shared collection (a
# therapy's supplies) is also corrected by whoever the collection is shared
# with; deleting it stays the buyer's.
class SupplyPurchasePolicy < ApplicationPolicy
  def create? = true
  def update? = owner? || shared?
  def destroy? = owner?

  private

  def shared? = record.collection&.shared_with?(user) || false
end
