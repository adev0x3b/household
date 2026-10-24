# frozen_string_literal: true

# A preview of a branch on dev can ask for a fresh database (the schema
# loaded whole, the demo seeded again): the press remembers whether it did.
class AddFreshToDeploymentRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :deployment_requests, :fresh, :boolean, default: false, null: false
  end
end
