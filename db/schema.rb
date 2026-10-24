# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_23_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "unaccent"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "analyte_aliases", force: :cascade do |t|
    t.bigint "analyte_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index "profile_id, lower((name)::text)", name: "index_analyte_aliases_on_profile_id_and_lower_name", unique: true
    t.index ["analyte_id"], name: "index_analyte_aliases_on_analyte_id"
  end

  create_table "analytes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index "profile_id, lower((name)::text)", name: "index_analytes_on_profile_id_and_lower_name", unique: true
  end

  create_table "appointment_details", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "occurrence_id"
    t.integer "kind"
    t.string "counterpart"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "occurrence_id"], name: "index_appointment_details_on_event_id_and_occurrence_id", unique: true, nulls_not_distinct: true
    t.index ["occurrence_id"], name: "index_appointment_details_on_occurrence_id"
    t.check_constraint "occurrence_id IS NOT NULL OR kind IS NOT NULL", name: "appointment_details_series_row_complete"
  end

  create_table "assistant_change_sets", force: :cascade do |t|
    t.jsonb "acknowledged_warnings", default: [], null: false
    t.datetime "applied_at"
    t.bigint "assistant_chat_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "display", default: [], null: false
    t.jsonb "intents", default: [], null: false
    t.jsonb "operations", default: [], null: false
    t.bigint "profile_id", null: false
    t.jsonb "shown_warnings", default: [], null: false
    t.integer "status", default: 0, null: false
    t.jsonb "undo_log", default: [], null: false
    t.boolean "undoable", default: true, null: false
    t.datetime "undone_at"
    t.datetime "updated_at", null: false
    t.index ["assistant_chat_id", "status"], name: "index_assistant_change_sets_on_assistant_chat_id_and_status"
    t.index ["profile_id"], name: "index_assistant_change_sets_on_profile_id"
  end

  create_table "assistant_chats", force: :cascade do |t|
    t.boolean "cancelled", default: false, null: false
    t.datetime "created_at", null: false
    t.string "locale", default: "en", null: false
    t.bigint "profile_id", null: false
    t.datetime "replying_since"
    t.bigint "ruby_llm_model_id", null: false
    t.string "time_zone"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["profile_id", "updated_at"], name: "index_assistant_chats_on_profile_id_and_updated_at"
    t.index ["ruby_llm_model_id"], name: "index_assistant_chats_on_ruby_llm_model_id"
  end

  create_table "assistant_messages", force: :cascade do |t|
    t.bigint "assistant_chat_id", null: false
    t.boolean "cache_until_here", default: false, null: false
    t.jsonb "citations"
    t.text "content"
    t.datetime "created_at", null: false
    t.string "finish_reason"
    t.boolean "hidden", default: false, null: false
    t.jsonb "raw_content"
    t.jsonb "raw_reasoning"
    t.string "role", null: false
    t.jsonb "server_tool_calls"
    t.text "thinking_signature"
    t.text "thinking_text"
    t.datetime "updated_at", null: false
    t.index ["assistant_chat_id"], name: "index_assistant_messages_on_assistant_chat_id"
  end

  create_table "assistant_reply_failures", force: :cascade do |t|
    t.bigint "assistant_chat_id", null: false
    t.integer "reason", null: false
    t.datetime "created_at", null: false
    t.index ["assistant_chat_id"], name: "index_assistant_reply_failures_on_assistant_chat_id"
  end

  create_table "assistant_settings", force: :cascade do |t|
    t.text "anthropic_api_key"
    t.integer "context_tokens"
    t.datetime "created_at", null: false
    t.integer "max_output_tokens"
    t.string "model"
    t.string "ollama_url"
    t.text "openai_api_key"
    t.string "provider"
    t.decimal "temperature", precision: 3, scale: 2
    t.string "thinking_effort"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.index ["updated_by_id"], name: "index_assistant_settings_on_updated_by_id"
  end

  create_table "book_shares", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.datetime "created_at", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id", "profile_id"], name: "index_book_shares_on_book_id_and_profile_id", unique: true
    t.index ["profile_id"], name: "index_book_shares_on_profile_id"
  end

  create_table "books", force: :cascade do |t|
    t.string "author", null: false
    t.integer "cover_id"
    t.string "cover_url"
    t.datetime "created_at", null: false
    t.date "finished_on"
    t.string "genres", default: [], null: false, array: true
    t.string "isbn", limit: 13
    t.text "notes"
    t.bigint "profile_id", null: false
    t.integer "rating"
    t.date "started_on"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "volume"
    t.index ["genres"], name: "index_books_on_genres", using: :gin
    t.index ["profile_id", "isbn"], name: "index_books_on_profile_id_and_isbn", unique: true, where: "(isbn IS NOT NULL)"
    t.index ["profile_id", "status"], name: "index_books_on_profile_id_and_status"
    t.check_constraint "finished_on >= started_on", name: "books_finished_after_started"
    t.check_constraint "isbn::text ~ '^[0-9]{13}$'::text", name: "books_isbn_format"
    t.check_constraint "rating >= 1 AND rating <= 5", name: "books_rating_range"
    t.check_constraint "volume >= 1", name: "books_volume_positive"
  end

  create_table "bookshelf_shares", force: :cascade do |t|
    t.bigint "bookshelf_id", null: false
    t.datetime "created_at", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["bookshelf_id", "profile_id"], name: "index_bookshelf_shares_on_bookshelf_id_and_profile_id", unique: true
    t.index ["profile_id"], name: "index_bookshelf_shares_on_profile_id"
  end

  create_table "bookshelves", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["profile_id"], name: "index_bookshelves_on_profile_id", unique: true
  end

  create_table "calendar_watches", force: :cascade do |t|
    t.bigint "profile_id", null: false
    t.string "year_month", limit: 7, null: false
    t.string "subscription", null: false
    t.datetime "seen_at", null: false
    t.index ["profile_id", "seen_at"], name: "index_calendar_watches_on_profile_id_and_seen_at"
    t.index ["seen_at"], name: "index_calendar_watches_on_seen_at"
    t.index ["subscription"], name: "index_calendar_watches_on_subscription", unique: true
  end

  create_table "collection_shares", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "collection_id", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_id", "profile_id"], name: "index_collection_shares_on_collection_id_and_profile_id", unique: true
    t.index ["profile_id"], name: "index_collection_shares_on_profile_id"
  end

  create_table "collections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.string "name", null: false
    t.bigint "profile_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "section", default: "healthcare", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "updated_by_id"
    t.index ["profile_id", "section"], name: "index_collections_on_profile_id_and_section"
    t.index ["updated_by_id"], name: "index_collections_on_updated_by_id"
  end

  create_table "conversation_participants", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "joined_at", null: false
    t.bigint "last_read_message_id"
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "profile_id"], name: "index_conversation_participants_on_conversation_and_profile", unique: true
    t.index ["last_read_message_id"], name: "index_conversation_participants_on_last_read_message_id"
    t.index ["profile_id"], name: "index_conversation_participants_on_profile_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "direct_key"
    t.bigint "household_id", null: false
    t.integer "kind", default: 0, null: false
    t.datetime "last_message_at"
    t.string "name", limit: 60
    t.datetime "updated_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "updated_by_id"
    t.index ["created_by_id"], name: "index_conversations_on_created_by_id"
    t.index ["direct_key"], name: "index_conversations_on_direct_key", unique: true
    t.index ["household_id"], name: "index_conversations_on_household_id"
    t.index ["household_id"], name: "index_conversations_one_household_chat", unique: true, where: "(kind = 1)"
    t.index ["updated_by_id"], name: "index_conversations_on_updated_by_id"
    t.check_constraint "(kind = 0) = (direct_key IS NOT NULL)", name: "conversations_direct_key_on_direct"
    t.check_constraint "name IS NULL OR kind = 1", name: "conversations_name_on_household"
  end

  create_table "deployment_requests", force: :cascade do |t|
    t.integer "action", null: false
    t.datetime "created_at", null: false
    t.string "destination"
    t.datetime "finished_at"
    t.boolean "fresh", default: false, null: false
    t.bigint "profile_id", null: false
    t.text "reason"
    t.string "ref"
    t.bigint "run_id"
    t.string "run_url"
    t.integer "status", default: 0, null: false
    t.string "summary"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["profile_id"], name: "index_deployment_requests_on_profile_id"
    t.index ["run_id"], name: "index_deployment_requests_on_run_id"
    t.index ["status", "created_at"], name: "index_deployment_requests_on_status_and_created_at"
  end

  create_table "event_exclusions", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.date "date", null: false
    t.time "time"
    t.index ["event_id", "date", "time"], name: "index_event_exclusions_on_event_id_and_date_and_time", unique: true, nulls_not_distinct: true
  end

  create_table "event_reminder_deliveries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_reminder_id", null: false
    t.date "date", null: false
    t.time "time"
    t.index ["event_reminder_id", "date", "time"], name: "index_event_reminder_deliveries_on_reminder_and_slot", unique: true, nulls_not_distinct: true
  end

  create_table "event_reminders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.integer "offset_minutes", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "profile_id", "offset_minutes"], name: "index_event_reminders_on_event_profile_and_offset", unique: true
    t.index ["profile_id"], name: "index_event_reminders_on_profile_id"
    t.check_constraint "offset_minutes > 0", name: "event_reminders_offset_minutes_positive"
  end

  create_table "event_shares", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "profile_id"], name: "index_event_shares_on_event_id_and_profile_id", unique: true
    t.index ["profile_id"], name: "index_event_shares_on_profile_id"
  end

  create_table "event_slots", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.time "time", null: false
    t.string "anchor"
    t.integer "position", default: 0, null: false
    t.index ["event_id", "position"], name: "index_event_slots_on_event_id_and_position", unique: true
    t.index ["event_id", "time"], name: "index_event_slots_on_event_id_and_time", unique: true
  end

  create_table "events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "starts_on", null: false
    t.bigint "collection_id"
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.string "type", null: false
    t.string "title"
    t.text "notes"
    t.string "location"
    t.time "start_time"
    t.integer "duration_minutes"
    t.text "rrule"
    t.integer "lock_version", default: 0, null: false
    t.bigint "updated_by_id"
    t.date "unsaved_from"
    t.index ["collection_id"], name: "index_events_on_collection_id"
    t.index ["profile_id", "type"], name: "index_events_on_profile_id_and_type"
    t.index ["starts_on"], name: "index_events_on_starts_on"
    t.index ["type"], name: "index_events_on_type"
    t.index ["updated_by_id"], name: "index_events_on_updated_by_id"
    t.check_constraint "duration_minutes > 0", name: "events_duration_minutes_positive"
  end

  create_table "grocery_list_items", force: :cascade do |t|
    t.boolean "checked", default: false, null: false
    t.datetime "checked_at"
    t.datetime "created_at", null: false
    t.bigint "grocery_list_id", null: false
    t.bigint "ingredient_id", null: false
    t.decimal "quantity", precision: 10, scale: 3
    t.bigint "unit_id"
    t.datetime "updated_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "updated_by_id"
    t.index ["grocery_list_id", "ingredient_id"], name: "index_grocery_list_items_on_grocery_list_id_and_ingredient_id", unique: true
    t.index ["ingredient_id"], name: "index_grocery_list_items_on_ingredient_id"
    t.index ["unit_id"], name: "index_grocery_list_items_on_unit_id"
    t.index ["updated_by_id"], name: "index_grocery_list_items_on_updated_by_id"
    t.check_constraint "quantity > 0::numeric", name: "grocery_list_items_quantity_positive"
  end

  create_table "grocery_list_shares", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "grocery_list_id", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["grocery_list_id", "profile_id"], name: "index_grocery_list_shares_on_grocery_list_id_and_profile_id", unique: true
    t.index ["profile_id"], name: "index_grocery_list_shares_on_profile_id"
  end

  create_table "grocery_lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "profile_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "updated_by_id"
    t.index ["profile_id"], name: "index_grocery_lists_on_profile_id"
    t.index ["updated_by_id"], name: "index_grocery_lists_on_updated_by_id"
  end

  create_table "households", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "EUR", null: false
    t.string "name", null: false
    t.bigint "owner_id"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_households_on_owner_id"
    t.index ["slug"], name: "index_households_on_slug", unique: true
    t.check_constraint "currency::text ~ '^[A-Z]{3}$'::text", name: "households_currency_format"
    t.check_constraint "slug::text ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::text", name: "households_slug_format"
  end

  create_table "ingredient_purchases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "grocery_list_item_id"
    t.bigint "ingredient_id", null: false
    t.bigint "profile_id", null: false
    t.date "purchased_on", null: false
    t.decimal "quantity", precision: 10, scale: 3, null: false
    t.bigint "unit_id"
    t.datetime "updated_at", null: false
    t.index ["grocery_list_item_id"], name: "index_ingredient_purchases_on_grocery_list_item_id"
    t.index ["ingredient_id", "purchased_on"], name: "index_ingredient_purchases_on_ingredient_id_and_purchased_on"
    t.index ["profile_id"], name: "index_ingredient_purchases_on_profile_id"
    t.index ["unit_id"], name: "index_ingredient_purchases_on_unit_id"
    t.check_constraint "quantity > 0::numeric", name: "ingredient_purchases_quantity_positive"
  end

  create_table "ingredients", force: :cascade do |t|
    t.integer "category", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "profile_id", null: false
    t.decimal "quantity", precision: 10, scale: 3, default: "0.0", null: false
    t.bigint "unit_id"
    t.datetime "updated_at", null: false
    t.index "profile_id, lower((name)::text)", name: "index_ingredients_on_profile_id_and_lower_name", unique: true
    t.index ["unit_id"], name: "index_ingredients_on_unit_id"
    t.check_constraint "quantity >= 0::numeric", name: "ingredients_quantity_not_negative"
  end

  create_table "lab_test_result_details", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "occurrence_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "occurrence_id"], name: "index_lab_test_result_details_on_event_id_and_occurrence_id", unique: true, nulls_not_distinct: true
    t.index ["occurrence_id"], name: "index_lab_test_result_details_on_occurrence_id"
  end

  create_table "lab_test_result_entries", force: :cascade do |t|
    t.bigint "analyte_id", null: false
    t.datetime "created_at", null: false
    t.bigint "unit_id"
    t.datetime "updated_at", null: false
    t.string "value", null: false
    t.bigint "occurrence_id", null: false
    t.index ["analyte_id"], name: "index_lab_test_result_entries_on_analyte_id"
    t.index ["occurrence_id", "analyte_id"], name: "index_lab_test_result_entries_on_occurrence_id_and_analyte_id", unique: true
    t.index ["unit_id"], name: "index_lab_test_result_entries_on_unit_id"
  end

  create_table "lexicon_eval_cases", force: :cascade do |t|
    t.string "concept", null: false
    t.boolean "confirmed", default: false, null: false
    t.datetime "created_at", null: false
    t.text "dose_sentence", null: false
    t.string "english_plural"
    t.bigint "lexicon_language_id", null: false
    t.string "model"
    t.string "native_plural", null: false
    t.string "native_singular", null: false
    t.text "purchase_sentence", null: false
    t.datetime "updated_at", null: false
    t.index ["lexicon_language_id", "concept"], name: "index_lexicon_eval_cases_on_lexicon_language_id_and_concept", unique: true
  end

  create_table "lexicon_forms", force: :cascade do |t|
    t.string "key", null: false
    t.bigint "lexicon_import_id", null: false
    t.bigint "lexicon_lemma_id", null: false
    t.index ["lexicon_import_id", "key"], name: "index_lexicon_forms_on_lexicon_import_id_and_key"
    t.index ["lexicon_lemma_id"], name: "index_lexicon_forms_on_lexicon_lemma_id"
  end

  create_table "lexicon_imports", force: :cascade do |t|
    t.datetime "cancel_requested_at"
    t.datetime "created_at", null: false
    t.text "error"
    t.string "failed_step"
    t.datetime "finished_at"
    t.string "job_id"
    t.string "language", null: false
    t.integer "lemma_count", default: 0, null: false
    t.jsonb "report", default: {}, null: false
    t.string "source_etag"
    t.datetime "source_last_modified"
    t.string "source_url"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["language", "status"], name: "index_lexicon_imports_on_language_and_status"
  end

  create_table "lexicon_languages", force: :cascade do |t|
    t.text "cases_error"
    t.datetime "cases_writing_since"
    t.jsonb "checks", default: [], null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "head", default: "first", null: false
    t.integer "min_lemmas", default: 1000, null: false
    t.string "role", default: "translated", null: false
    t.datetime "updated_at", null: false
    t.string "wiktionary", null: false
    t.index ["code"], name: "index_lexicon_languages_on_code", unique: true
    t.index ["wiktionary"], name: "index_lexicon_languages_on_wiktionary", unique: true
    t.check_constraint "min_lemmas > 0", name: "lexicon_languages_min_lemmas_positive"
  end

  create_table "lexicon_lemmas", force: :cascade do |t|
    t.string "key", null: false
    t.bigint "lexicon_import_id", null: false
    t.string "word", null: false
    t.index ["lexicon_import_id", "key"], name: "index_lexicon_lemmas_on_lexicon_import_id_and_key"
  end

  create_table "lexicon_meanings", force: :cascade do |t|
    t.string "key", null: false
    t.integer "kind", default: 0, null: false
    t.bigint "lexicon_import_id", null: false
    t.bigint "lexicon_lemma_id", null: false
    t.boolean "qualified", default: false, null: false
    t.integer "rank", default: 0, null: false
    t.index ["lexicon_import_id", "key"], name: "index_lexicon_meanings_on_lexicon_import_id_and_key"
    t.index ["lexicon_lemma_id"], name: "index_lexicon_meanings_on_lexicon_lemma_id"
  end

  create_table "link_approvals", force: :cascade do |t|
    t.integer "action_kind", null: false
    t.datetime "base_updated_at"
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.string "error"
    t.bigint "event_id"
    t.string "event_type", null: false
    t.bigint "link_id", null: false
    t.date "date"
    t.bigint "owner_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.jsonb "preview", default: [], null: false
    t.bigint "requester_id", null: false
    t.string "scope"
    t.integer "source", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "occurrence_id"
    t.time "time"
    t.integer "failure"
    t.index ["event_id", "date", "time", "action_kind", "requester_id"], name: "index_link_approvals_one_pending_per_dose", unique: true, where: "((status = 0) AND (event_id IS NOT NULL))", nulls_not_distinct: true
    t.index ["event_id"], name: "index_link_approvals_on_event_id"
    t.index ["link_id"], name: "index_link_approvals_on_link_id"
    t.index ["occurrence_id"], name: "index_link_approvals_on_occurrence_id"
    t.index ["owner_id", "status"], name: "index_link_approvals_on_owner_id_and_status"
    t.index ["requester_id", "status"], name: "index_link_approvals_on_requester_id_and_status"
  end

  create_table "link_grants", force: :cascade do |t|
    t.integer "create_level", default: 2, null: false
    t.datetime "created_at", null: false
    t.integer "delete_level", default: 2, null: false
    t.string "event_type", null: false
    t.bigint "grantee_id", null: false
    t.bigint "grantor_id", null: false
    t.bigint "link_id", null: false
    t.integer "read_level", default: 1, null: false
    t.datetime "updated_at", null: false
    t.integer "write_level", default: 2, null: false
    t.index ["grantee_id", "read_level", "grantor_id", "event_type"], name: "index_link_grants_for_reading"
    t.index ["grantor_id", "grantee_id", "event_type"], name: "index_link_grants_on_grantor_id_and_grantee_id_and_event_type", unique: true
    t.index ["link_id"], name: "index_link_grants_on_link_id"
  end

  create_table "links", force: :cascade do |t|
    t.datetime "accepted_at"
    t.bigint "addressee_id", null: false
    t.datetime "created_at", null: false
    t.string "pair_key", null: false
    t.bigint "requester_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["addressee_id"], name: "index_links_on_addressee_id"
    t.index ["pair_key"], name: "index_links_on_pair_key", unique: true
    t.index ["requester_id"], name: "index_links_on_requester_id"
    t.check_constraint "requester_id <> addressee_id", name: "links_two_people"
  end

  create_table "meal_consumptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "ingredient_id", null: false
    t.decimal "quantity", precision: 10, scale: 3, null: false
    t.datetime "updated_at", null: false
    t.bigint "occurrence_id", null: false
    t.index ["ingredient_id"], name: "index_meal_consumptions_on_ingredient_id"
    t.index ["occurrence_id"], name: "index_meal_consumptions_on_occurrence_id"
    t.check_constraint "quantity > 0::numeric", name: "meal_consumptions_quantity_positive"
  end

  create_table "meal_details", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "occurrence_id"
    t.integer "kind"
    t.integer "meal_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "occurrence_id"], name: "index_meal_details_on_event_id_and_occurrence_id", unique: true, nulls_not_distinct: true
    t.index ["occurrence_id"], name: "index_meal_details_on_occurrence_id"
    t.check_constraint "occurrence_id IS NOT NULL OR kind IS NOT NULL", name: "meal_details_series_row_complete"
  end

  create_table "meal_recipes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "meal_details_id", null: false
    t.index ["meal_details_id", "recipe_id"], name: "index_meal_recipes_on_meal_details_id_and_recipe_id", unique: true
    t.index ["recipe_id"], name: "index_meal_recipes_on_recipe_id"
  end

  create_table "medication_details", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "occurrence_id"
    t.integer "kind"
    t.integer "area"
    t.integer "side"
    t.decimal "quantity", precision: 10, scale: 2
    t.string "unit"
    t.decimal "pill_count", precision: 10, scale: 3
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "occurrence_id"], name: "index_medication_details_on_event_id_and_occurrence_id", unique: true, nulls_not_distinct: true
    t.index ["occurrence_id"], name: "index_medication_details_on_occurrence_id"
    t.check_constraint "occurrence_id IS NOT NULL OR kind IS NOT NULL", name: "medication_details_series_row_complete"
  end

  create_table "message_reactions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "emoji", limit: 32, null: false
    t.bigint "message_id", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "profile_id", "emoji"], name: "index_message_reactions_on_message_id_and_profile_id_and_emoji", unique: true
    t.index ["profile_id"], name: "index_message_reactions_on_profile_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "body"
    t.uuid "client_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "sender_id", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "id"], name: "index_messages_on_conversation_id_and_id"
    t.index ["sender_id", "client_id"], name: "index_messages_on_sender_id_and_client_id", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.integer "kind", null: false
    t.bigint "profile_id", null: false
    t.datetime "read_at"
    t.bigint "subject_id"
    t.string "subject_title"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_notifications_on_actor_id"
    t.index ["profile_id", "created_at"], name: "index_notifications_on_profile_id_and_created_at"
    t.index ["profile_id", "read_at"], name: "index_notifications_on_profile_id_and_read_at"
    t.index ["subject_type", "subject_id"], name: "index_notifications_on_subject"
  end

  create_table "occurrences", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.date "date", null: false
    t.time "time"
    t.string "anchor"
    t.integer "status", default: 0, null: false
    t.datetime "completed_at"
    t.string "skipped_reason"
    t.string "title"
    t.text "notes"
    t.string "location"
    t.time "start_time"
    t.integer "duration_minutes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "updated_by_id"
    t.index ["date"], name: "index_occurrences_on_date"
    t.index ["event_id", "date", "time"], name: "index_occurrences_on_event_id_and_date_and_time", unique: true, nulls_not_distinct: true
    t.index ["event_id", "status"], name: "index_occurrences_on_event_id_and_status"
    t.index ["id", "event_id"], name: "index_occurrences_on_id_and_event_id", unique: true
    t.index ["updated_by_id"], name: "index_occurrences_on_updated_by_id"
    t.check_constraint "(status = 2) = (completed_at IS NOT NULL)", name: "occurrences_completed_at_with_completed"
    t.check_constraint "duration_minutes > 0", name: "occurrences_duration_minutes_positive"
    t.check_constraint "skipped_reason IS NULL OR status = 4", name: "occurrences_skipped_reason_with_skipped"
  end

  create_table "platform_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "demo_password"
    t.text "deploy_dispatch_token"
    t.text "google_books_api_key"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.string "setup_code_digest"
    t.boolean "assistant"
    t.boolean "uploads"
    t.boolean "pictures"
    t.boolean "invitations"
    t.boolean "push_notifications"
    t.boolean "release_check"
    t.integer "assistant_messages_per_day"
    t.integer "book_lookups_per_day"
    t.bigint "files_quota"
    t.integer "household_size"
    t.integer "invitations_per_member"
    t.index ["updated_by_id"], name: "index_platform_settings_on_updated_by_id"
    t.check_constraint "assistant_messages_per_day >= 0", name: "platform_settings_assistant_messages_per_day_not_negative"
    t.check_constraint "book_lookups_per_day >= 0", name: "platform_settings_book_lookups_per_day_not_negative"
    t.check_constraint "files_quota > 0", name: "platform_settings_files_quota_positive"
    t.check_constraint "household_size > 0", name: "platform_settings_household_size_positive"
    t.check_constraint "invitations_per_member > 0", name: "platform_settings_invitations_per_member_positive"
  end

  create_table "profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "first_name"
    t.integer "gender"
    t.bigint "household_id", null: false
    t.datetime "invitation_accepted_at"
    t.datetime "invitation_created_at"
    t.integer "invitation_limit"
    t.datetime "invitation_sent_at"
    t.string "invitation_token"
    t.integer "invitations_count", default: 0
    t.bigint "invited_by_id"
    t.string "invited_by_type"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "locale"
    t.datetime "locked_at"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.integer "sign_in_count", default: 0, null: false
    t.string "time_zone"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index "lower((username)::text)", name: "index_profiles_on_lower_username", unique: true
    t.index ["email"], name: "index_profiles_on_email", unique: true
    t.index ["household_id"], name: "index_profiles_on_household_id"
    t.index ["invitation_token"], name: "index_profiles_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_profiles_on_invited_by_id"
    t.index ["invited_by_type", "invited_by_id"], name: "index_profiles_on_invited_by"
    t.index ["reset_password_token"], name: "index_profiles_on_reset_password_token", unique: true
    t.check_constraint "invitation_token IS NOT NULL OR COALESCE(btrim(username::text), ''::text) <> ''::text", name: "profiles_username_unless_invited"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth_key", null: false
    t.datetime "created_at", null: false
    t.text "endpoint", null: false
    t.datetime "last_succeeded_at"
    t.string "origin", null: false
    t.string "p256dh_key", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["profile_id"], name: "index_push_subscriptions_on_profile_id"
  end

  create_table "recipe_ingredients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "ingredient_id", null: false
    t.decimal "quantity", precision: 10, scale: 3, null: false
    t.bigint "recipe_id", null: false
    t.bigint "unit_id"
    t.datetime "updated_at", null: false
    t.index ["ingredient_id"], name: "index_recipe_ingredients_on_ingredient_id"
    t.index ["recipe_id", "ingredient_id"], name: "index_recipe_ingredients_on_recipe_id_and_ingredient_id", unique: true
    t.index ["unit_id"], name: "index_recipe_ingredients_on_unit_id"
    t.check_constraint "quantity > 0::numeric", name: "recipe_ingredients_quantity_positive"
  end

  create_table "recipe_shares", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "profile_id", null: false
    t.bigint "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["profile_id"], name: "index_recipe_shares_on_profile_id"
    t.index ["recipe_id", "profile_id"], name: "index_recipe_shares_on_recipe_id_and_profile_id", unique: true
  end

  create_table "recipe_steps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "instruction", null: false
    t.integer "position", null: false
    t.bigint "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["recipe_id"], name: "index_recipe_steps_on_recipe_id"
  end

  create_table "recipes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "updated_by_id"
    t.index ["profile_id"], name: "index_recipes_on_profile_id"
    t.index ["updated_by_id"], name: "index_recipes_on_updated_by_id"
  end

  create_table "reference_ranges", force: :cascade do |t|
    t.bigint "analyte_id", null: false
    t.datetime "created_at", null: false
    t.decimal "critical_high", precision: 10, scale: 3
    t.decimal "critical_low", precision: 10, scale: 3
    t.decimal "high", precision: 10, scale: 3
    t.decimal "low", precision: 10, scale: 3
    t.integer "sex", default: 0, null: false
    t.bigint "unit_id", null: false
    t.datetime "updated_at", null: false
    t.index ["analyte_id", "unit_id", "sex"], name: "index_reference_ranges_on_analyte_unit_sex", unique: true
    t.index ["unit_id"], name: "index_reference_ranges_on_unit_id"
    t.check_constraint "critical_high >= high", name: "reference_ranges_critical_high_at_least_high"
    t.check_constraint "critical_low <= low", name: "reference_ranges_critical_low_at_most_low"
    t.check_constraint "low < high", name: "reference_ranges_low_below_high"
    t.check_constraint "num_nonnulls(low, high, critical_low, critical_high) > 0", name: "reference_ranges_some_bound"
  end

  create_table "ruby_llm_batches", force: :cascade do |t|
    t.string "batch_protocol"
    t.jsonb "chat_ids", default: []
    t.string "chat_type"
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.string "provider_batch_id", null: false
    t.string "raw_status"
    t.jsonb "reported_cost"
    t.jsonb "request_counts"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "provider_batch_id"], name: "index_ruby_llm_batches_on_provider_and_provider_batch_id", unique: true
    t.index ["status"], name: "index_ruby_llm_batches_on_status"
  end

  create_table "ruby_llm_models", force: :cascade do |t|
    t.jsonb "capabilities", default: []
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.jsonb "metadata", default: {}
    t.jsonb "modalities", default: {}
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.jsonb "pricing", default: {}
    t.string "provider", null: false
    t.datetime "unlisted_at"
    t.datetime "updated_at", null: false
    t.index ["capabilities"], name: "index_ruby_llm_models_on_capabilities", using: :gin
    t.index ["family"], name: "index_ruby_llm_models_on_family"
    t.index ["modalities"], name: "index_ruby_llm_models_on_modalities", using: :gin
    t.index ["provider", "model_id"], name: "index_ruby_llm_models_on_provider_and_model_id", unique: true
  end

  create_table "ruby_llm_tool_calls", force: :cascade do |t|
    t.string "approval"
    t.jsonb "arguments", default: {}
    t.datetime "created_at", null: false
    t.bigint "message_id", null: false
    t.string "message_type", null: false
    t.string "name", null: false
    t.boolean "remote", default: false, null: false
    t.bigint "result_id"
    t.string "result_type"
    t.text "thought_signature"
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index ["message_type", "message_id"], name: "index_ruby_llm_tool_calls_on_message_type_and_message_id"
    t.index ["name"], name: "index_ruby_llm_tool_calls_on_name"
    t.index ["result_type", "result_id"], name: "index_ruby_llm_tool_calls_on_result_type_and_result_id"
    t.index ["tool_call_id"], name: "index_ruby_llm_tool_calls_on_tool_call_id", unique: true
  end

  create_table "ruby_llm_usages", force: :cascade do |t|
    t.decimal "cache_read_cost", precision: 16, scale: 10
    t.integer "cache_read_tokens"
    t.decimal "cache_write_cost", precision: 16, scale: 10
    t.integer "cache_write_tokens"
    t.bigint "chat_id", null: false
    t.string "chat_type", null: false
    t.datetime "created_at", null: false
    t.decimal "input_cost", precision: 16, scale: 10
    t.integer "input_tokens"
    t.bigint "message_id"
    t.string "message_type"
    t.string "model", null: false
    t.string "operation", null: false
    t.decimal "output_cost", precision: 16, scale: 10
    t.integer "output_tokens"
    t.string "provider", null: false
    t.string "status", null: false
    t.decimal "thinking_cost", precision: 16, scale: 10
    t.integer "thinking_tokens"
    t.decimal "total_cost", precision: 16, scale: 10
    t.datetime "updated_at", null: false
    t.index ["chat_type", "chat_id"], name: "index_ruby_llm_usages_on_chat_type_and_chat_id"
    t.index ["message_type", "message_id"], name: "index_ruby_llm_usages_on_message_type_and_message_id"
    t.index ["status"], name: "index_ruby_llm_usages_on_status"
    t.check_constraint "operation::text = ANY (ARRAY['chat'::character varying::text, 'embedding'::character varying::text, 'moderation'::character varying::text, 'image'::character varying::text, 'speech'::character varying::text, 'transcription'::character varying::text, 'ocr'::character varying::text, 'rerank'::character varying::text])"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'succeeded'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])"
  end

  create_table "supplies", force: :cascade do |t|
    t.integer "category", default: 0, null: false
    t.datetime "created_at", null: false
    t.decimal "low_stock_threshold", precision: 10, scale: 3
    t.string "name", null: false
    t.integer "pao_days"
    t.bigint "profile_id", null: false
    t.string "unit_label", null: false
    t.datetime "updated_at", null: false
    t.index "profile_id, lower((name)::text)", name: "index_supplies_on_profile_id_and_lower_name", unique: true
  end

  create_table "supply_consumptions", force: :cascade do |t|
    t.datetime "consumed_at", null: false
    t.datetime "created_at", null: false
    t.decimal "quantity", precision: 10, scale: 3, null: false
    t.bigint "supply_id", null: false
    t.bigint "supply_purchase_id"
    t.datetime "updated_at", null: false
    t.bigint "occurrence_id", null: false
    t.index ["occurrence_id"], name: "index_supply_consumptions_on_occurrence_id"
    t.index ["supply_id"], name: "index_supply_consumptions_on_supply_id"
    t.index ["supply_purchase_id"], name: "index_supply_consumptions_on_supply_purchase_id"
    t.check_constraint "quantity > 0::numeric", name: "supply_consumptions_quantity_positive"
  end

  create_table "supply_purchases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "expires_on"
    t.bigint "collection_id"
    t.date "opened_on"
    t.integer "pao_days_override"
    t.bigint "profile_id", null: false
    t.date "purchased_on", null: false
    t.decimal "quantity_purchased", precision: 10, scale: 3, null: false
    t.decimal "quantity_remaining", precision: 10, scale: 3, null: false
    t.bigint "supply_id", null: false
    t.datetime "updated_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "updated_by_id"
    t.index ["collection_id"], name: "index_supply_purchases_on_collection_id"
    t.index ["profile_id"], name: "index_supply_purchases_on_profile_id"
    t.index ["supply_id"], name: "index_supply_purchases_on_supply_id"
    t.index ["updated_by_id"], name: "index_supply_purchases_on_updated_by_id"
    t.check_constraint "quantity_purchased > 0::numeric", name: "supply_purchases_quantity_purchased_positive"
  end

  create_table "supply_uses", force: :cascade do |t|
    t.bigint "medication_details_id", null: false
    t.bigint "supply_id", null: false
    t.decimal "quantity", precision: 10, scale: 3, null: false
    t.index ["medication_details_id", "supply_id"], name: "index_supply_uses_on_medication_details_id_and_supply_id", unique: true
    t.index ["supply_id"], name: "index_supply_uses_on_supply_id"
    t.check_constraint "quantity > 0::numeric", name: "supply_uses_quantity_positive"
  end

  create_table "task_details", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "occurrence_id"
    t.integer "priority"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "occurrence_id"], name: "index_task_details_on_event_id_and_occurrence_id", unique: true, nulls_not_distinct: true
    t.index ["occurrence_id"], name: "index_task_details_on_occurrence_id"
    t.check_constraint "occurrence_id IS NOT NULL OR priority IS NOT NULL", name: "task_details_series_row_complete"
  end

  create_table "transaction_details", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "occurrence_id"
    t.integer "kind"
    t.integer "category"
    t.bigint "amount_cents"
    t.string "currency", limit: 3
    t.integer "payment_method"
    t.string "counterparty"
    t.bigint "counterparty_profile_id"
    t.string "about_type"
    t.bigint "about_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["about_type", "about_id"], name: "index_transaction_details_on_about"
    t.index ["counterparty_profile_id"], name: "index_transaction_details_on_counterparty_profile_id"
    t.index ["event_id", "occurrence_id"], name: "index_transaction_details_on_event_id_and_occurrence_id", unique: true, nulls_not_distinct: true
    t.index ["occurrence_id"], name: "index_transaction_details_on_occurrence_id"
    t.check_constraint "amount_cents > 0", name: "transaction_details_amount_cents_positive"
    t.check_constraint "currency IS NULL OR currency::text ~ '^[A-Z]{3}$'::text", name: "transaction_details_currency_format"
    t.check_constraint "occurrence_id IS NOT NULL OR kind IS NOT NULL AND category IS NOT NULL AND amount_cents IS NOT NULL AND currency IS NOT NULL AND payment_method IS NOT NULL", name: "transaction_details_series_row_complete"
    t.check_constraint "occurrence_id IS NULL OR counterparty_profile_id IS NULL", name: "transaction_details_counterparty_on_series"
  end

  create_table "units", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "household_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "household_id, lower((name)::text)", name: "index_units_on_household_id_and_lower_name", unique: true
  end

  create_table "upload_activities", force: :cascade do |t|
    t.integer "action", null: false
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.string "ip"
    t.bigint "profile_id"
    t.bigint "upload_id", null: false
    t.bigint "upload_link_id"
    t.string "user_agent", limit: 255
    t.index ["profile_id"], name: "index_upload_activities_on_profile_id"
    t.index ["upload_id", "created_at"], name: "index_upload_activities_on_upload_id_and_created_at"
    t.index ["upload_link_id"], name: "index_upload_activities_on_upload_link_id"
  end

  create_table "upload_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "downloads_count", default: 0, null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.integer "max_downloads"
    t.string "password_digest"
    t.bigint "profile_id", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "upload_id", null: false
    t.index ["profile_id"], name: "index_upload_links_on_profile_id"
    t.index ["token_digest"], name: "index_upload_links_on_token_digest", unique: true
    t.index ["upload_id"], name: "index_upload_links_on_upload_id"
    t.check_constraint "downloads_count >= 0", name: "upload_links_downloads_count_not_negative"
    t.check_constraint "max_downloads > 0", name: "upload_links_max_downloads_positive"
  end

  create_table "upload_shares", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "profile_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "upload_id", null: false
    t.index ["profile_id"], name: "index_upload_shares_on_profile_id"
    t.index ["upload_id", "profile_id"], name: "index_upload_shares_on_upload_id_and_profile_id", unique: true
  end

  create_table "uploads", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "completed_at"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name", limit: 255, null: false
    t.bigint "profile_id", null: false
    t.bigint "received_bytes", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_uploads_on_key", unique: true
    t.index ["profile_id"], name: "index_uploads_on_profile_id"
    t.index ["status", "updated_at"], name: "index_uploads_on_status_and_updated_at"
    t.check_constraint "byte_size > 0", name: "uploads_byte_size_positive"
    t.check_constraint "received_bytes >= 0", name: "uploads_received_bytes_not_negative"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "analyte_aliases", "analytes"
  add_foreign_key "analyte_aliases", "profiles"
  add_foreign_key "analytes", "profiles"
  add_foreign_key "appointment_details", "events"
  add_foreign_key "appointment_details", "occurrences", column: ["occurrence_id", "event_id"], primary_key: ["id", "event_id"], name: "appointment_details_day_of_its_series", on_update: :cascade, on_delete: :cascade
  add_foreign_key "assistant_change_sets", "assistant_chats"
  add_foreign_key "assistant_change_sets", "profiles"
  add_foreign_key "assistant_chats", "profiles"
  add_foreign_key "assistant_chats", "ruby_llm_models"
  add_foreign_key "assistant_messages", "assistant_chats"
  add_foreign_key "assistant_reply_failures", "assistant_chats"
  add_foreign_key "assistant_settings", "profiles", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "book_shares", "books"
  add_foreign_key "book_shares", "profiles"
  add_foreign_key "books", "profiles"
  add_foreign_key "bookshelf_shares", "bookshelves"
  add_foreign_key "bookshelf_shares", "profiles"
  add_foreign_key "bookshelves", "profiles"
  add_foreign_key "calendar_watches", "profiles", on_delete: :cascade
  add_foreign_key "collection_shares", "collections"
  add_foreign_key "collection_shares", "profiles"
  add_foreign_key "collections", "profiles"
  add_foreign_key "collections", "profiles", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "conversation_participants", "conversations"
  add_foreign_key "conversation_participants", "messages", column: "last_read_message_id", on_delete: :nullify
  add_foreign_key "conversation_participants", "profiles"
  add_foreign_key "conversations", "households"
  add_foreign_key "conversations", "profiles", column: "created_by_id", on_delete: :nullify
  add_foreign_key "conversations", "profiles", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "deployment_requests", "profiles"
  add_foreign_key "event_exclusions", "events", on_delete: :cascade
  add_foreign_key "event_reminder_deliveries", "event_reminders"
  add_foreign_key "event_reminders", "events"
  add_foreign_key "event_reminders", "profiles"
  add_foreign_key "event_shares", "events"
  add_foreign_key "event_shares", "profiles"
  add_foreign_key "event_slots", "events", on_delete: :cascade
  add_foreign_key "events", "collections"
  add_foreign_key "events", "profiles"
  add_foreign_key "events", "profiles", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "grocery_list_items", "grocery_lists"
  add_foreign_key "grocery_list_items", "ingredients"
  add_foreign_key "grocery_list_items", "profiles", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "grocery_list_items", "units"
  add_foreign_key "grocery_list_shares", "grocery_lists"
  add_foreign_key "grocery_list_shares", "profiles"
  add_foreign_key "grocery_lists", "profiles"
  add_foreign_key "grocery_lists", "profiles", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "households", "profiles", column: "owner_id", on_delete: :nullify
  add_foreign_key "ingredient_purchases", "grocery_list_items", on_delete: :nullify
  add_foreign_key "ingredient_purchases", "ingredients"
  add_foreign_key "ingredient_purchases", "profiles"
  add_foreign_key "ingredient_purchases", "units"
  add_foreign_key "ingredients", "profiles"
  add_foreign_key "ingredients", "units"
  add_foreign_key "lab_test_result_details", "events"
  add_foreign_key "lab_test_result_details", "occurrences", column: ["occurrence_id", "event_id"], primary_key: ["id", "event_id"], name: "lab_test_result_details_day_of_its_series", on_update: :cascade, on_delete: :cascade
  add_foreign_key "lab_test_result_entries", "analytes"
  add_foreign_key "lab_test_result_entries", "occurrences"
  add_foreign_key "lab_test_result_entries", "units"
  add_foreign_key "lexicon_eval_cases", "lexicon_languages", on_delete: :cascade
  add_foreign_key "lexicon_forms", "lexicon_imports", on_delete: :cascade
  add_foreign_key "lexicon_forms", "lexicon_lemmas", on_delete: :cascade
  add_foreign_key "lexicon_lemmas", "lexicon_imports", on_delete: :cascade
  add_foreign_key "lexicon_meanings", "lexicon_imports", on_delete: :cascade
  add_foreign_key "lexicon_meanings", "lexicon_lemmas", on_delete: :cascade
  add_foreign_key "link_approvals", "events", on_delete: :nullify
  add_foreign_key "link_approvals", "links"
  add_foreign_key "link_approvals", "occurrences", on_delete: :nullify
  add_foreign_key "link_approvals", "profiles", column: "owner_id"
  add_foreign_key "link_approvals", "profiles", column: "requester_id"
  add_foreign_key "link_grants", "links"
  add_foreign_key "link_grants", "profiles", column: "grantee_id"
  add_foreign_key "link_grants", "profiles", column: "grantor_id"
  add_foreign_key "links", "profiles", column: "addressee_id"
  add_foreign_key "links", "profiles", column: "requester_id"
  add_foreign_key "meal_consumptions", "ingredients"
  add_foreign_key "meal_consumptions", "occurrences"
  add_foreign_key "meal_details", "events"
  add_foreign_key "meal_details", "occurrences", column: ["occurrence_id", "event_id"], primary_key: ["id", "event_id"], name: "meal_details_day_of_its_series", on_update: :cascade, on_delete: :cascade
  add_foreign_key "meal_recipes", "meal_details", column: "meal_details_id", on_delete: :cascade
  add_foreign_key "meal_recipes", "recipes"
  add_foreign_key "medication_details", "events"
  add_foreign_key "medication_details", "occurrences", column: ["occurrence_id", "event_id"], primary_key: ["id", "event_id"], name: "medication_details_day_of_its_series", on_update: :cascade, on_delete: :cascade
  add_foreign_key "message_reactions", "messages"
  add_foreign_key "message_reactions", "profiles"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "profiles", column: "sender_id"
  add_foreign_key "notifications", "profiles"
  add_foreign_key "notifications", "profiles", column: "actor_id", on_delete: :nullify
  add_foreign_key "occurrences", "events"
  add_foreign_key "occurrences", "profiles", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "platform_settings", "profiles", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "profiles", "households"
  add_foreign_key "push_subscriptions", "profiles"
  add_foreign_key "recipe_ingredients", "ingredients"
  add_foreign_key "recipe_ingredients", "recipes"
  add_foreign_key "recipe_ingredients", "units"
  add_foreign_key "recipe_shares", "profiles"
  add_foreign_key "recipe_shares", "recipes"
  add_foreign_key "recipe_steps", "recipes"
  add_foreign_key "recipes", "profiles"
  add_foreign_key "recipes", "profiles", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "reference_ranges", "analytes"
  add_foreign_key "reference_ranges", "units"
  add_foreign_key "supplies", "profiles"
  add_foreign_key "supply_consumptions", "occurrences"
  add_foreign_key "supply_consumptions", "supplies"
  add_foreign_key "supply_consumptions", "supply_purchases"
  add_foreign_key "supply_purchases", "collections"
  add_foreign_key "supply_purchases", "profiles"
  add_foreign_key "supply_purchases", "profiles", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "supply_purchases", "supplies"
  add_foreign_key "supply_uses", "medication_details", column: "medication_details_id", on_delete: :cascade
  add_foreign_key "supply_uses", "supplies"
  add_foreign_key "task_details", "events"
  add_foreign_key "task_details", "occurrences", column: ["occurrence_id", "event_id"], primary_key: ["id", "event_id"], name: "task_details_day_of_its_series", on_update: :cascade, on_delete: :cascade
  add_foreign_key "transaction_details", "events"
  add_foreign_key "transaction_details", "occurrences", column: ["occurrence_id", "event_id"], primary_key: ["id", "event_id"], name: "transaction_details_day_of_its_series", on_update: :cascade, on_delete: :cascade
  add_foreign_key "transaction_details", "profiles", column: "counterparty_profile_id"
  add_foreign_key "units", "households"
  add_foreign_key "upload_activities", "profiles"
  add_foreign_key "upload_activities", "upload_links"
  add_foreign_key "upload_activities", "uploads"
  add_foreign_key "upload_links", "profiles"
  add_foreign_key "upload_links", "uploads"
  add_foreign_key "upload_shares", "profiles"
  add_foreign_key "upload_shares", "uploads"
  add_foreign_key "uploads", "profiles"
end
