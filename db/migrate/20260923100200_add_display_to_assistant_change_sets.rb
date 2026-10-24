# frozen_string_literal: true

class AddDisplayToAssistantChangeSets < ActiveRecord::Migration[8.1]
  # What the chat card shows per operation (localized summary + status),
  # kept so an applied or undone set renders without being recompiled.
  def change
    add_column :assistant_change_sets, :display, :jsonb, null: false, default: []
  end
end
