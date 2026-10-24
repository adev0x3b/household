# frozen_string_literal: true

# The household's messages: one conversation for the whole household and
# one per pair of housemates, each person's place in it (and how far they
# have read), the messages, and the emoji reactions to them. Pictures are
# Active Storage attachments on a message.
class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :household, null: false, foreign_key: true
      t.integer :kind, null: false, default: 0
      t.string :name, limit: 60
      # "<lower id>:<higher id>" for a direct conversation: one per pair.
      t.string :direct_key
      t.references :created_by, foreign_key: { to_table: :profiles, on_delete: :nullify }
      t.datetime :last_message_at
      t.timestamps
    end
    add_index :conversations, :direct_key, unique: true
    # One household conversation per household.
    add_index :conversations, :household_id, unique: true, where: "kind = 1", name: "index_conversations_one_household_chat"

    create_table :conversation_participants do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      # The newest message they have seen (the read receipt); nil: none yet.
      t.bigint :last_read_message_id
      t.datetime :joined_at, null: false
      t.timestamps
    end
    add_index :conversation_participants, [ :conversation_id, :profile_id ], unique: true

    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :sender, null: false, foreign_key: { to_table: :profiles }
      t.text :body
      # Minted by the composer: sending the same message twice (a retry on a
      # bad connection) saves it once.
      t.uuid :client_id, null: false
      # Unsent by its sender: the row stays as a placeholder, emptied.
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :messages, [ :conversation_id, :id ]
    add_index :messages, [ :sender_id, :client_id ], unique: true

    add_foreign_key :conversation_participants, :messages, column: :last_read_message_id, on_delete: :nullify

    create_table :message_reactions do |t|
      t.references :message, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.string :emoji, null: false, limit: 32
      t.timestamps
    end
    add_index :message_reactions, [ :message_id, :profile_id, :emoji ], unique: true
  end
end
