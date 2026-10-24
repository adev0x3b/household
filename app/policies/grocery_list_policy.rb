# frozen_string_literal: true

# A grocery list is kept by its owner and everyone it is shared with: any of
# them adds, buys, renames, finishes or reopens it. Deleting it is the
# owner's alone.
class GroceryListPolicy < ApplicationPolicy
  def create? = true
  def show? = owner? || shared?
  def update? = owner? || shared?
  def finish? = update?
  def reopen? = update?
  def destroy? = owner?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.accessible_by(user)
  end
end
