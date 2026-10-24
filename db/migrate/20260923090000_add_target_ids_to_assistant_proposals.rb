# frozen_string_literal: true

class AddTargetIdsToAssistantProposals < ActiveRecord::Migration[8.1]
  # One confirmation card can cover several records ("delete all lab reports").
  def up
    add_column :assistant_proposals, :target_ids, :jsonb, null: false, default: []
    execute "UPDATE assistant_proposals SET target_ids = jsonb_build_array(target_id)"
  end

  def down
    remove_column :assistant_proposals, :target_ids
  end
end
