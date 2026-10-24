# frozen_string_literal: true

# A device that asked for push notifications (Web Push): the endpoint its
# browser's push service gave it, the keys that encrypt what's sent there,
# and the site it subscribed on (pushes link back to the same origin).
class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      t.references :profile, null: false, foreign_key: true
      t.text :endpoint, null: false
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false
      t.string :origin, null: false
      t.string :user_agent
      t.datetime :last_succeeded_at
      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true
  end
end
