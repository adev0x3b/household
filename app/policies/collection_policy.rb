# frozen_string_literal: true

# A collection (Healthcare's therapy) is seen and changed by its owner and
# everyone it is shared with; deleting it is the owner's alone.
class CollectionPolicy < ApplicationPolicy
  def create? = true
  def show? = owner? || shared?
  def update? = owner? || shared?
  def destroy? = owner?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.accessible_by(user)
  end
end
