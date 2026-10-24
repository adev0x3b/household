# frozen_string_literal: true

# A profile only ever sees and reads its own notifications.
class NotificationPolicy < ApplicationPolicy
  def index? = true
  def mark_all_read? = true
  def show? = owner?
  def read? = owner?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.where(profile: user)
  end
end
