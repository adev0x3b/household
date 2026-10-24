# frozen_string_literal: true

# A day's details name both the day and its series, and the next migrations
# make the database hold the two to agree: a composite foreign key to
# (id, event_id), which Postgres needs a unique index on. Built
# concurrently, so neither version of the app waits on a lock.
class IndexOccurrencesOnIdAndEvent < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :occurrences, %i[id event_id], name: "index_occurrences_on_id_and_event_id", unique: true,
                                             algorithm: :concurrently, if_not_exists: true
  end
end
