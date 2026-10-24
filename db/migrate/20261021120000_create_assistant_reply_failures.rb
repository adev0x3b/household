# frozen_string_literal: true

# A reply that ended without an answer is kept, so the thread still says
# why once the page is drawn again. The table is new, so the version still
# serving never reads it.
class CreateAssistantReplyFailures < ActiveRecord::Migration[8.1]
  def change
    create_table :assistant_reply_failures do |t|
      t.references :assistant_chat, null: false, foreign_key: true
      t.integer :reason, null: false
      t.datetime :created_at, null: false
    end
  end
end
