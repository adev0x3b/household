# frozen_string_literal: true

# A household's page (its people and invitations) is its members' — and the
# app admin's, who creates households and helps their first member in.
class HouseholdPolicy < ApplicationPolicy
  def show? = member? || user.admin?
  # Members invite where the installation lets them (Platform.invitations?); the admin always.
  def invite? = show? && (user.admin? || Platform.invitations?)

  # One's own household; every household, for the admin.
  class Scope < ApplicationPolicy::Scope
    def resolve = user.admin? ? scope.all : scope.where(id: user.household_id)
  end

  private

  def member? = user.household_id == record.id
end
