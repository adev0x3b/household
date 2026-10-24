# frozen_string_literal: true

# A request about a series taken several times a day is about one dose of
# it, so it keeps that dose's time beside its date (none for an untimed
# day), and a person has one pending request per dose and action rather
# than per day. The new index is built before the old one goes, both
# concurrently, so neither version of the app waits on a lock. The version
# still serving writes no time, which the new index allows wherever the
# old one did.
class AddTheDoseToLinkApprovals < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # The requests still waiting, which the index covers.
  PENDING = "status = 0 AND event_id IS NOT NULL"

  def change
    add_column :link_approvals, :time, :time, if_not_exists: true
    add_index :link_approvals, %i[event_id date time action_kind requester_id],
              name: "index_link_approvals_one_pending_per_dose", unique: true, nulls_not_distinct: true, where: PENDING,
              algorithm: :concurrently, if_not_exists: true
    remove_index :link_approvals, %i[event_id date action_kind requester_id],
                 name: "index_link_approvals_one_pending", unique: true, where: PENDING,
                 algorithm: :concurrently, if_exists: true
  end
end
