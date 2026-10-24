# frozen_string_literal: true

# The assistant's provider, credentials, model and tuning, set on
# /assistant/settings (Assistant::Setting). One row; a blank column falls
# back to the environment (.env), so nothing changes until an admin saves.
class CreateAssistantSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :assistant_settings do |t|
      t.string :provider
      t.string :model
      t.string :ollama_url
      t.text :anthropic_api_key
      t.text :openai_api_key
      t.integer :context_tokens
      t.decimal :temperature, precision: 3, scale: 2
      t.string :thinking_effort
      t.integer :max_output_tokens
      t.references :updated_by, foreign_key: { to_table: :profiles, on_delete: :nullify }
      t.timestamps
    end
  end
end
