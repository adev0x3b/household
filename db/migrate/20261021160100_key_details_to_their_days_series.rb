# frozen_string_literal: true

# A details row for one day names the day and the series, and the model
# validates that the day is one of that series'. Each table's key to its day
# now takes both columns, so the database refuses a row that pairs a day
# with another series. A series' own row has no day, and Postgres checks no
# key with a NULL in it, so it is left alone.
#
# It deletes with the day, as the key it replaces does, and follows the day
# if the day ever moves to another series, so the two can't drift apart.
# Added without checking the rows there are, which would hold a lock on the
# tables while the version still serving writes to them; the next migration
# checks them and drops the keys these replace.
class KeyDetailsToTheirDaysSeries < ActiveRecord::Migration[8.1]
  DETAILS = %i[appointment_details lab_test_result_details meal_details medication_details task_details
               transaction_details].freeze

  def change
    DETAILS.each do |table|
      add_foreign_key table, :occurrences, column: %i[occurrence_id event_id], primary_key: %i[id event_id],
                                           name: "#{table}_day_of_its_series", on_delete: :cascade,
                                           on_update: :cascade, validate: false
    end
  end
end
