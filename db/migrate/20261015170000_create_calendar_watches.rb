# frozen_string_literal: true

# Which calendar months someone has open, one row per open month (a
# CalendarChannel subscription), shared by every process: the web server
# that holds the connection, the job worker that pushes a day card. A row
# is refreshed while its page is open and stops counting once it isn't.
class CreateCalendarWatches < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_watches do |t|
      t.references :profile, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :year_month, null: false, limit: 7
      t.string :subscription, null: false
      t.datetime :seen_at, null: false
      t.index :subscription, unique: true
      t.index %i[profile_id seen_at]
      t.index :seen_at
    end
  end
end
