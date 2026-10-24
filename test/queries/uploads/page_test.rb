# frozen_string_literal: true

require "test_helper"

class Uploads::PageTest < ActiveSupport::TestCase
  setup do
    @alice = profiles(:alice)
    @upload = keep_file(@alice, name: "lease.pdf")
  end

  test "its links, newest first" do
    older, = UploadLink.mint(upload: @upload, by: @alice)
    travel 1.minute
    newer, = UploadLink.mint(upload: @upload, by: @alice)

    assert_equal [ newer, older ], Uploads::Page.new(@upload).links
  ensure
    travel_back
  end

  test "its trail, newest first and only the latest entries" do
    (Uploads::Page::ACTIVITY + 1).times { |minute| travel_to(minute.minutes.from_now) { UploadActivity.record(@upload, :downloaded, actor: @alice) } }

    activity = Uploads::Page.new(@upload).activity
    assert_equal Uploads::Page::ACTIVITY, activity.size
    assert_equal @upload.upload_activities.maximum(:created_at), activity.first.created_at
  end
end
