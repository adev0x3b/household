# frozen_string_literal: true

class CreateAssistantChangeSets < ActiveRecord::Migration[8.1]
  # Everything one user message asks the assistant to change, compiled and
  # applied as a unit (see Assistant::ChangeSet). Replaces drafts and
  # deletion proposals.
  def change
    create_table :assistant_change_sets do |t|
      t.references :profile, null: false, foreign_key: true
      t.references :assistant_chat, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.jsonb :intents, null: false, default: []
      t.jsonb :operations, null: false, default: []
      t.jsonb :acknowledged_warnings, null: false, default: []
      t.jsonb :undo_log, null: false, default: []
      t.boolean :undoable, null: false, default: true
      t.datetime :applied_at
      t.datetime :undone_at
      t.timestamps
    end
    add_index :assistant_change_sets, [ :assistant_chat_id, :status ]
  end
end
