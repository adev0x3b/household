# frozen_string_literal: true

# What the admin pressed on /admin/deployment: who, what, where, which
# version, why, the GitHub run it became and how it ended (Deployment::Request).
class CreateDeploymentRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :deployment_requests do |t|
      t.references :profile, null: false, foreign_key: true
      t.integer :action, null: false
      t.string :destination
      t.string :version
      t.string :ref
      t.text :reason
      t.bigint :run_id
      t.string :run_url
      t.integer :status, null: false, default: 0
      t.string :summary
      t.datetime :finished_at
      t.timestamps
    end
    add_index :deployment_requests, [ :status, :created_at ]
    add_index :deployment_requests, :run_id
  end
end
