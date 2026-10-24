# frozen_string_literal: true

# Links between housemates. The record is a Link — for create? an unsaved
# one from the asker to the one asked.
#   create?   ask a housemate one isn't linked with yet (if they already
#             asked, asking back accepts theirs — Links::Request)
#   accept?   the one asked, while it's pending
#   destroy?  either side: declining or taking back one that waits, ending
#             one accepted
class LinkPolicy < ApplicationPolicy
  def create?
    return false unless record.requester_id == user.id && user.housemates.exists?(record.addressee_id)

    existing = Link.between(user, record.addressee)
    existing.nil? || (existing.pending? && existing.addressee_id == user.id)
  end

  def accept? = record.pending? && record.addressee_id == user.id
  def destroy? = record.involves?(user)
end
