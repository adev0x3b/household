# frozen_string_literal: true

# The lexicon: nouns from Wiktionary (kaikki.org extracts), per language, so
# the assistant can tell that "needle" is the saved "Aghi". Every row belongs
# to the import that loaded it: a new import loads beside the active one and
# replaces it only after its checks pass (Lexicon::Import).
class CreateLexiconTables < ActiveRecord::Migration[8.1]
  def change
    create_table :lexicon_imports do |t|
      t.string :language, null: false
      t.integer :status, null: false, default: 0
      t.string :source_url
      t.string :source_etag
      t.datetime :source_last_modified
      t.datetime :started_at
      t.datetime :finished_at
      t.string :failed_step
      t.text :error
      t.jsonb :report, null: false, default: {}
      t.integer :lemma_count, null: false, default: 0
      t.timestamps
    end
    add_index :lexicon_imports, [ :language, :status ]

    create_table :lexicon_lemmas do |t|
      t.references :lexicon_import, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :word, null: false
      t.string :key, null: false
    end
    add_index :lexicon_lemmas, [ :lexicon_import_id, :key ]

    create_table :lexicon_forms do |t|
      t.references :lexicon_import, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :lexicon_lemma, null: false, foreign_key: { on_delete: :cascade }
      t.string :key, null: false
    end
    add_index :lexicon_forms, [ :lexicon_import_id, :key ]

    create_table :lexicon_meanings do |t|
      t.references :lexicon_import, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :lexicon_lemma, null: false, foreign_key: { on_delete: :cascade }
      t.string :key, null: false
      t.integer :rank, null: false, default: 0
      t.boolean :qualified, null: false, default: false
      t.integer :kind, null: false, default: 0
    end
    add_index :lexicon_meanings, [ :lexicon_import_id, :key ]
  end
end
