# frozen_string_literal: true

class CreateAssistantDraftsAndProposals < ActiveRecord::Migration[8.1]
  def change
    # Work the assistant has started but can't save yet (missing fields, or
    # a possible duplicate the user hasn't confirmed). Never shown on the
    # calendar; committed into real records by Assistant::DraftCommitter.
    create_table :assistant_drafts do |t|
      t.references :profile, null: false, foreign_key: true
      t.references :assistant_chat, foreign_key: true
      t.integer :kind, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :payload, null: false, default: {}
      t.jsonb :missing, null: false, default: []
      t.jsonb :warnings, null: false, default: []
      # Possible duplicates the user already said to ignore.
      t.jsonb :acknowledged_warnings, null: false, default: []
      t.jsonb :committed_records, null: false, default: []
      t.timestamps
    end
    add_index :assistant_drafts, [ :profile_id, :status ]

    # Destructive actions the assistant may only propose; the user confirms
    # them with a button handled by Assistant::ProposalsController.
    create_table :assistant_proposals do |t|
      t.references :profile, null: false, foreign_key: true
      t.references :assistant_chat, null: false, foreign_key: true
      t.string :action, null: false
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.string :scope, null: false, default: "occurrence"
      t.string :summary, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end
  end
end
