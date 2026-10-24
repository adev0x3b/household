# frozen_string_literal: true

# An assistant chat is private to the profile that started it.
class Assistant::ChatPolicy < ApplicationPolicy
  def index?   = true
  def create?  = true
  def show?    = owner?
  def update?  = owner?
  def destroy? = owner?
  # Photos go with a message where the installation has pictures on (Platform.pictures?).
  def attach? = owner? && Platform.pictures?

  # The raw tool-call trace (?debug=1): its owner, when they are an admin
  # or the app runs in development.
  def debug? = owner? && (user.admin? || Rails.env.development?)

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.where(profile: user)
  end
end
