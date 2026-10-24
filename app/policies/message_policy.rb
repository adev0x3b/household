# frozen_string_literal: true

# Writing goes to the people of the conversation, with pictures where the
# installation has them on (Platform.pictures?); unsending is the sender's alone.
class MessagePolicy < ApplicationPolicy
  def create? = record.conversation.participant?(user)
  def attach? = create? && Platform.pictures?
  def destroy? = record.sender_id == user.id && !record.deleted?
  def react? = record.conversation.participant?(user) && !record.deleted?
end
