# frozen_string_literal: true

# The mail the app sends, a row per mail to one person (Emails::Enqueue),
# sent by Emails::Drain within the installation's and the household's
# budgets. A row keeps ids, dates and times, never words; an address only
# for a notice that must reach the one the person had when it was queued
# (an old address, the one confirmed when the password changed), and only
# until the row ends. Why a row waits or failed is a reason the admin's page
# words, with the relay's reply or the error's class as its detail.
class CreateOutgoingEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :outgoing_emails do |t|
      t.references :profile, null: false, foreign_key: true, index: false
      t.integer :kind, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :data, null: false, default: {}
      t.integer :attempts, null: false, default: 0
      t.datetime :not_before, null: false
      t.datetime :expires_at, null: false
      t.datetime :claimed_at
      t.datetime :held_for_settings_at
      t.datetime :sent_at
      t.string :message_id
      t.integer :reason
      t.string :detail
      t.timestamps

      t.index %i[profile_id kind created_at]
      t.index %i[status not_before]
      t.index :claimed_at
      t.check_constraint "attempts >= 0", name: "outgoing_emails_attempts_not_negative"
    end
  end
end
