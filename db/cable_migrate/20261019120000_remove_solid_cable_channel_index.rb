# frozen_string_literal: true

# Solid Cable 4 finds a channel's messages by its hash alone, so the index on
# the channel's name only slowed every broadcast's insert.
class RemoveSolidCableChannelIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    remove_index :solid_cable_messages, :channel,
                 name: "index_solid_cable_messages_on_channel", algorithm: :concurrently
  end
end
