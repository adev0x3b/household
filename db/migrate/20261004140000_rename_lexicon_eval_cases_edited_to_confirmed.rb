# frozen_string_literal: true

# A case counts once a person has vouched for it — by fixing it or by
# confirming it as written — not only when it was edited.
class RenameLexiconEvalCasesEditedToConfirmed < ActiveRecord::Migration[8.1]
  def change
    rename_column :lexicon_eval_cases, :edited, :confirmed
  end
end
