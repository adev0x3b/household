# frozen_string_literal: true

# One person's place in a conversation, and the newest message they have
# seen (`last_read_message_id`: their read receipt, what the unread counts
# and "Seen by" are made of). Made by Conversation.household_conversation /
# .direct_between, never by a form: who takes part follows from the
# household, not from a choice.
class ConversationParticipant < ApplicationRecord
  belongs_to :conversation
  belongs_to :profile
  belongs_to :last_read_message, class_name: "Message", optional: true

  before_validation { self.joined_at ||= Time.current }

  validates :profile_id, uniqueness: { scope: :conversation_id }
  validates_within_household :profile, of: :conversation

  # Reads up to `message`, never backwards (a read receipt doesn't unread):
  # one conditional UPDATE, so two reads arriving together can't undo each
  # other the way a check in Ruby, then a write, could. True when it moved.
  def read_up_to!(message)
    return false if message.nil? || message.conversation_id != conversation_id

    moved = self.class.where(id: id).where("last_read_message_id IS NULL OR last_read_message_id < ?", message.id)
      .update_all(last_read_message_id: message.id, updated_at: Time.current)
    return false if moved.zero?

    self.last_read_message_id = message.id
    clear_attribute_changes(%w[last_read_message_id])
    true
  end

  def read?(message) = last_read_message_id.present? && last_read_message_id >= message.id
end
