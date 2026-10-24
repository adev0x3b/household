# frozen_string_literal: true

# What can be done to a person on a household's page (Views::Households::People):
#
#   destroy?            remove them, with everything they kept: the admin
#                       (anyone but themselves) or their household's owner
#                       (anyone of the household but themselves).
#   password_link?      a link for a member to set a password (a seeded
#                       account, a lost password): the admin or the
#                       owner, for anyone but themselves. Not their inviter:
#                       setting someone's password is becoming them, and an
#                       invitation is no reason to hold that for good.
#   renew_invitation?   a new link for an invitation still waiting: who
#                       invited them, or the admin — the people who can
#                       hand the link over
#   cancel_invitation?  take an invitation back: the same, and the owner
class ProfilePolicy < ApplicationPolicy
  def destroy?
    return false if record == user

    user.admin? || owner_of_record?
  end

  def password_link? = !record.invitation_pending? && record != user && (user.admin? || owner_of_record?)

  def renew_invitation? = record.invitation_pending? && (user.admin? || inviter?)

  def cancel_invitation? = record.invitation_pending? && (user.admin? || inviter? || owner_of_record?)

  # The people of one's own household; everyone, for the admin.
  class Scope < ApplicationPolicy::Scope
    def resolve = user.admin? ? scope.all : scope.where(household_id: user.household_id)
  end

  private

  def inviter? = record.invited_by_id == user.id && record.invited_by_type == "Profile"

  def owner_of_record? = record.household_id == user.household_id && record.household.owner_id == user.id
end
