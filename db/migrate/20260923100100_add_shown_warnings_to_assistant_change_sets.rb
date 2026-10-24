# frozen_string_literal: true

class AddShownWarningsToAssistantChangeSets < ActiveRecord::Migration[8.1]
  # Possible duplicates already shown to the model; only those can be
  # waived by a later confirm (the model can't pre-accept unseen warnings).
  def change
    add_column :assistant_change_sets, :shown_warnings, :jsonb, null: false, default: []
  end
end
