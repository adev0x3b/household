# frozen_string_literal: true

# An ingredient belongs to one profile: its owner sees and changes it, for
# the ingredients page and the assistant alike.
class IngredientPolicy < ApplicationPolicy
  def show? = owner?
  def create? = true
  def update? = owner?
  def destroy? = owner?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.where(profile: user)
  end
end
