# frozen_string_literal: true

# A conversation is for the people in it, and only them: a housemate who
# isn't a participant of a direct one can't read it. Anyone may open one
# with a housemate (the controller finds them among the housemates alone).
# Anyone in the household's conversation may rename it; a direct one has
# no name.
class ConversationPolicy < ApplicationPolicy
  def show? = participant?
  def create? = true
  def update? = participant? && record.household?
  def read? = participant?
  def older? = participant?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.accessible_by(user)
  end

  private

  def participant? = record.participant?(user)
end
