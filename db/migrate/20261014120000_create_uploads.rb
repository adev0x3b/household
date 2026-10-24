# frozen_string_literal: true

# The Files section: a file kept on the server (uploads: the upload in
# progress and the file once it is whole), who it is shared with
# (upload_shares), the links handed to people outside (upload_links: only
# the token's digest is kept) and everything that happened to it
# (upload_activities).
class CreateUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :uploads do |t|
      t.references :profile, null: false, foreign_key: true
      t.string :name, null: false, limit: 255
      t.string :content_type
      t.bigint :byte_size, null: false
      t.bigint :received_bytes, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.string :key, null: false
      t.string :checksum
      t.datetime :completed_at
      t.timestamps
    end
    add_index :uploads, :key, unique: true
    add_index :uploads, [ :status, :updated_at ]

    create_table :upload_shares do |t|
      t.references :upload, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.timestamps
    end
    add_index :upload_shares, [ :upload_id, :profile_id ], unique: true

    create_table :upload_links do |t|
      t.references :upload, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.integer :max_downloads
      t.integer :downloads_count, null: false, default: 0
      t.string :password_digest
      t.datetime :revoked_at
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :upload_links, :token_digest, unique: true

    create_table :upload_activities do |t|
      t.references :upload, null: false, foreign_key: true
      t.references :profile, foreign_key: true
      t.references :upload_link, foreign_key: true
      t.integer :action, null: false
      t.string :ip
      t.string :user_agent, limit: 255
      t.jsonb :data, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :upload_activities, [ :upload_id, :created_at ]
  end
end
