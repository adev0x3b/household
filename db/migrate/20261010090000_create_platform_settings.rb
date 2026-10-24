# frozen_string_literal: true

# What the admin sets for the whole app on /admin/settings (Platform::Setting):
# one row, its secrets encrypted by Active Record.
class CreatePlatformSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :platform_settings do |t|
      t.text :google_books_api_key
      t.text :deploy_dispatch_token
      t.text :demo_password
      t.references :updated_by, foreign_key: { to_table: :profiles, on_delete: :nullify }

      t.timestamps
    end
  end
end
