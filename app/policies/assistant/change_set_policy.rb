# frozen_string_literal: true

# A chat's changes are answered only by the person the assistant works for,
# and each button only while it makes sense.
class Assistant::ChangeSetPolicy < ApplicationPolicy
  def apply?  = owner? && record.awaiting_confirmation?
  def cancel? = owner? && record.in_progress?
  def undo?   = owner? && record.applied? && record.undoable
  def review? = owner? && record.in_progress?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.where(profile: user)
  end
end
