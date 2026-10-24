# frozen_string_literal: true

class CreateAssistantMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :assistant_messages, id: :bigint do |t|
      t.references :assistant_chat, null: false, foreign_key: { to_table: :assistant_chats }, type: :bigint
      t.string :role, null: false
      t.text :content
      t.boolean :cache_until_here, null: false, default: false
      t.text :thinking_text
      t.text :thinking_signature

      t.jsonb :citations
      t.jsonb :server_tool_calls
      t.jsonb :raw_content
      t.jsonb :raw_reasoning

      t.string :finish_reason
      t.timestamps
    end
  end
end
