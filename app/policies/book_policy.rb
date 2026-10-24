# frozen_string_literal: true

# A book is its owner's to change; a housemate it (or the owner's whole
# shelf) is shared with reads it. The assistant authorizes every change
# through here too.
class BookPolicy < ApplicationPolicy
  def index? = true
  def create? = true
  def scan? = true
  def lookup? = true
  def show? = owner? || shared?
  def update? = owner?
  def destroy? = owner?
  def change_status? = owner?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.accessible_by(user)
  end

  private

  # The book itself, or the owner's whole shelf: Book.with_everything loads
  # both, so asking costs no query.
  def shared? = super || record.profile.bookshelf&.shared_with?(user) || false
end
