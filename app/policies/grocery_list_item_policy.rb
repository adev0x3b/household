# frozen_string_literal: true

# A grocery list's item is kept by whoever can see the list: its owner and
# everyone it is shared with. A new item is built through its list
# (`list.grocery_list_items.build`), so it always has one to ask.
class GroceryListItemPolicy < ApplicationPolicy
  def create? = owner? || shared?
  def update? = owner? || shared?
  def destroy? = owner? || shared?
  def check? = owner? || shared?
  def uncheck? = owner? || shared?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.accessible_by(user)
  end

  private

  # The list's owner and whoever it is shared with.
  def owning_record = record.grocery_list
end
