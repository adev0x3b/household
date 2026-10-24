# frozen_string_literal: true

# A supply belongs to the profile that added it. Someone a therapy is shared
# with sees the supplies bought for it (Supply.accessible_by) and may restock
# them, but only the owner changes or deletes the supply itself.
class SupplyPolicy < ApplicationPolicy
  def show? = Supply.accessible_by(user).exists?(id: record.id)
  def create? = owner?
  def update? = owner?
  def destroy? = owner?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.accessible_by(user)
  end
end
