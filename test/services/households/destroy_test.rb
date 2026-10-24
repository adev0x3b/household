# frozen_string_literal: true

require "test_helper"

# A household goes with everything it owns — every row that reaches it
# through the schema's references (OwnedRows), not a list kept by hand —
# and nothing of another household. A table added later is part of it the
# day it is created, and this test asks for a row of the example household in it.
class Households::DestroyTest < ActiveSupport::TestCase
  include ActionDispatch::TestProcess::FixtureFile

  test "a household goes with everything it owns, as the schema says, and nothing of another one" do
    give_the_example_household_a_row_everywhere
    rows = OwnedRows.new
    ours = rows.of(households(:example))
    theirs = rows.of(households(:elsewhere))
    blobs = ActiveStorage::Attachment.where(id: ours.fetch("active_storage_attachments").to_a).pluck(:blob_id)
    paths = Upload.where(id: ours.fetch("uploads").to_a).map(&:path)

    assert_empty rows.ownable - ours.keys,
                 "the example household keeps nothing in these tables, so their deletion isn't tested: give it a row in each"

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { Households::Destroy.call(households(:example)) }

    left = ours.filter_map do |table, ids|
      kept = ActiveRecord::Base.connection.select_values("SELECT id FROM #{table} WHERE id IN (#{ids.to_a.join(", ")})")
      "#{table}: #{kept.size} of #{ids.size}" if kept.any?
    end
    assert_empty left, "the example household's rows still there"
    assert_equal theirs, rows.of(households(:elsewhere)), "nothing of another household is touched"
    assert_empty rows.dangling
    assert_not ActiveStorage::Blob.exists?(id: blobs), "a picture's bytes go with its attachment"
    assert paths.none? { File.exist?(_1) }, "a file's bytes go with it"
  end
end
