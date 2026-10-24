# frozen_string_literal: true

# Rails names an index after its table and columns, and falls back to a hash
# when that name is longer than Postgres allows. These two got the hash, so
# they get names a reader can tell apart. Renaming only changes the catalog.
class NameTheLongUniqueIndexes < ActiveRecord::Migration[8.1]
  def change
    rename_index :conversation_participants, "idx_on_conversation_id_profile_id_bfa3aba72b",
                 "index_conversation_participants_on_conversation_and_profile"
    rename_index :event_reminders, "idx_on_event_id_profile_id_offset_minutes_18471975cd",
                 "index_event_reminders_on_event_profile_and_offset"
  end
end
