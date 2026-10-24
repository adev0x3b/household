# frozen_string_literal: true

class CreateAssistantChats < ActiveRecord::Migration[8.1]
  def change
    create_table :assistant_chats, id: :bigint do |t|
      t.references :ruby_llm_model, null: false, foreign_key: { to_table: :ruby_llm_models }, type: :bigint
      t.references :profile, null: false, foreign_key: true
      t.string :title
      t.string :locale, null: false, default: "en"
      t.string :time_zone
      t.boolean :cancelled, null: false, default: false
      # Set while a reply job is running for this chat — one run at a time.
      t.datetime :replying_since
      t.timestamps
    end
    add_index :assistant_chats, [ :profile_id, :updated_at ]
  end
end
