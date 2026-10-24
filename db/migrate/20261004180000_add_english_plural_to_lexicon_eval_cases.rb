# frozen_string_literal: true

# The English plural a case's supply is named with when saved in English.
# Empty for the shared supplies (config/lexicon_eval_concepts.yml has it);
# set on the cases an admin creates for a supply of their own.
class AddEnglishPluralToLexiconEvalCases < ActiveRecord::Migration[8.1]
  def change
    add_column :lexicon_eval_cases, :english_plural, :string
  end
end
