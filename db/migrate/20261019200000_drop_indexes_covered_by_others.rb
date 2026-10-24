# frozen_string_literal: true

# Each of these indexes is on a column another index of its table starts
# with (a share's thing, before the thing and the person together). Postgres
# answers a lookup on that column from the longer index just as well, so
# the shorter one only costs a write on every insert and update. They go
# concurrently, so neither version of the app waits on a lock, and one at a
# time outside a transaction, so a run cut short can simply run again.
class DropIndexesCoveredByOthers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # The columns whose own index goes, per table.
  COVERED = {
    analyte_aliases: %i[profile_id],
    analytes: %i[profile_id],
    appointment_details: %i[event_id],
    assistant_change_sets: %i[assistant_chat_id],
    assistant_chats: %i[profile_id],
    book_shares: %i[book_id],
    books: %i[profile_id],
    bookshelf_shares: %i[bookshelf_id],
    collection_shares: %i[collection_id],
    collections: %i[profile_id],
    conversation_participants: %i[conversation_id],
    event_exclusions: %i[event_id],
    event_reminders: %i[event_id],
    event_shares: %i[event_id],
    event_slots: %i[event_id],
    events: %i[profile_id],
    grocery_list_items: %i[grocery_list_id],
    grocery_list_shares: %i[grocery_list_id],
    ingredient_purchases: %i[ingredient_id],
    ingredients: %i[profile_id],
    lab_test_result_details: %i[event_id],
    lab_test_result_entries: %i[occurrence_id],
    lexicon_eval_cases: %i[lexicon_language_id],
    link_approvals: %i[owner_id requester_id],
    link_grants: %i[grantee_id grantor_id],
    meal_details: %i[event_id],
    meal_recipes: %i[meal_details_id],
    medication_details: %i[event_id],
    message_reactions: %i[message_id],
    messages: %i[conversation_id sender_id],
    notifications: %i[profile_id],
    occurrences: %i[event_id],
    recipe_ingredients: %i[recipe_id],
    recipe_shares: %i[recipe_id],
    reference_ranges: %i[analyte_id],
    ruby_llm_models: %i[provider],
    supplies: %i[profile_id],
    supply_uses: %i[medication_details_id],
    task_details: %i[event_id],
    transaction_details: %i[event_id],
    units: %i[household_id],
    upload_activities: %i[upload_id],
    upload_shares: %i[upload_id]
  }.freeze

  def change
    COVERED.each do |table, columns|
      columns.each { |column| remove_index table, column, algorithm: :concurrently, if_exists: true }
    end
  end
end
