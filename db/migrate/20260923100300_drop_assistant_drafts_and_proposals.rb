# frozen_string_literal: true

class DropAssistantDraftsAndProposals < ActiveRecord::Migration[8.1]
  # Replaced by assistant_change_sets (drafts and deletion proposals are
  # both change sets now). Held only development data.
  def up
    drop_table :assistant_drafts
    drop_table :assistant_proposals
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
