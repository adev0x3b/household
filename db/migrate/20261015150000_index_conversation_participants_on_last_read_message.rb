# frozen_string_literal: true

# A read receipt's message: the one foreign key without an index, so every
# message deleted (a person's, all at once) scanned the receipts to clear.
class IndexConversationParticipantsOnLastReadMessage < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :conversation_participants, :last_read_message_id, algorithm: :concurrently
  end
end
