# frozen_string_literal: true

class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :profile, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :profiles, on_delete: :nullify }
      t.references :subject, polymorphic: true
      t.integer :kind, null: false
      t.string :subject_title
      t.jsonb :data, null: false, default: {}
      t.datetime :read_at

      t.timestamps
    end

    add_index :notifications, [ :profile_id, :read_at ]
    add_index :notifications, [ :profile_id, :created_at ]
  end
end
