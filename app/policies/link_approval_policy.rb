# frozen_string_literal: true

# A linked housemate's request about one's item: its owner gives it or
# declines it, its asker can take it back (Links::Approvals::Decide refuses
# one already answered).
class LinkApprovalPolicy < ApplicationPolicy
  def approve? = record.owner_id == user.id
  def destroy? = record.owner_id == user.id || record.requester_id == user.id

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.involving(user)
  end
end
