# frozen_string_literal: true

# Languages live in the database so the admin page can add one that isn't
# in config/lexicons.yml (which seeds the table, LexiconLanguage.ensure_defaults!),
# and each language keeps the cases its imports are tested against the agent
# with (Lexicon::EvalCases, Lexicon::AgentEval).
class CreateLexiconLanguagesAndEvalCases < ActiveRecord::Migration[8.1]
  def change
    create_table :lexicon_languages do |t|
      t.string :code, null: false
      t.string :wiktionary, null: false
      t.string :role, null: false, default: "translated"
      t.string :head, null: false, default: "first"
      t.integer :min_lemmas, null: false, default: 1000
      t.jsonb :checks, null: false, default: []
      t.timestamps
    end
    add_index :lexicon_languages, :code, unique: true
    add_index :lexicon_languages, :wiktionary, unique: true

    create_table :lexicon_eval_cases do |t|
      t.references :lexicon_language, null: false, foreign_key: { on_delete: :cascade }
      t.string :concept, null: false
      t.string :native_singular, null: false
      t.string :native_plural, null: false
      t.text :dose_sentence, null: false
      t.text :purchase_sentence, null: false
      t.string :model
      t.boolean :edited, null: false, default: false
      t.timestamps
    end
    add_index :lexicon_eval_cases, [ :lexicon_language_id, :concept ], unique: true
  end
end
