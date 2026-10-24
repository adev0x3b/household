# frozen_string_literal: true

class CreateLinks < ActiveRecord::Migration[8.1]
  def change
    # Two housemates who see each other's calendars: asked by one, accepted by the other.
    create_table :links do |t|
      t.references :requester, null: false, foreign_key: { to_table: :profiles }
      t.references :addressee, null: false, foreign_key: { to_table: :profiles }
      t.string :pair_key, null: false
      t.integer :status, null: false, default: 0
      t.datetime :accepted_at
      t.timestamps
    end
    add_index :links, :pair_key, unique: true

    # What a linked person may do with the other's items, per eventable type:
    # one row per direction and type, only while the link is accepted.
    create_table :link_grants do |t|
      t.references :link, null: false, foreign_key: true
      t.references :grantor, null: false, foreign_key: { to_table: :profiles }
      t.references :grantee, null: false, foreign_key: { to_table: :profiles }
      t.string :eventable_type, null: false
      t.integer :read_level, null: false, default: 1
      t.integer :write_level, null: false, default: 2
      t.integer :create_level, null: false, default: 2
      t.integer :delete_level, null: false, default: 2
      t.timestamps
    end
    add_index :link_grants, %i[grantor_id grantee_id eventable_type], unique: true
    add_index :link_grants, %i[grantee_id read_level grantor_id eventable_type], name: "index_link_grants_for_reading"

    # A change a linked person asked for, waiting for the owner's OK.
    create_table :link_approvals do |t|
      t.references :link, null: false, foreign_key: true
      t.references :requester, null: false, foreign_key: { to_table: :profiles }
      t.references :owner, null: false, foreign_key: { to_table: :profiles }
      t.string :eventable_type, null: false
      t.integer :action_kind, null: false
      t.integer :source, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.references :event, foreign_key: { on_delete: :nullify }
      t.bigint :record_id
      t.date :occurrence_date
      t.string :scope
      t.string :title, null: false
      t.jsonb :payload, null: false, default: {}
      t.jsonb :preview, null: false, default: []
      t.datetime :base_updated_at
      t.datetime :decided_at
      t.string :error
      t.timestamps
    end
    add_index :link_approvals, %i[owner_id status]
    add_index :link_approvals, %i[requester_id status]
    add_index :link_approvals, %i[event_id occurrence_date action_kind requester_id], unique: true,
                                                                                      where: "status = 0 AND event_id IS NOT NULL", name: "index_link_approvals_one_pending"
  end
end
