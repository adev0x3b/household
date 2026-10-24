# frozen_string_literal: true

require "test_helper"

class Uploads::FinishJobTest < ActiveSupport::TestCase
  test "the file is checked, fingerprinted, typed from its bytes and ready" do
    upload = Uploads::Create.call(owner: profiles(:alice), name: "report.pdf", byte_size: 12, content_type: "text/plain").upload
    Uploads::Append.call(upload, io: StringIO.new("%PDF-1.4\nabc"), offset: 0, length: 12)
    upload.reload
    assert_predicate upload, :processing?

    assert_no_difference -> { Notification.count } do # quick: no bell
      Uploads::FinishJob.perform_now(upload)
    end
    upload.reload
    assert_predicate upload, :ready?
    assert_equal Digest::SHA256.hexdigest("%PDF-1.4\nabc"), upload.checksum
    assert_equal "application/pdf", upload.content_type
    assert upload.completed_at
    assert_equal [ "uploaded" ], upload.upload_activities.pluck(:action)
  ensure
    Uploads::Storage.delete(upload.key)
  end

  test "a long upload rings the bell; one that came up short goes back to uploading" do
    upload = Uploads::Create.call(owner: profiles(:alice), name: "movie.bin", byte_size: 6).upload
    Uploads::Append.call(upload, io: StringIO.new("abcdef"), offset: 0, length: 6)
    File.truncate(upload.path, 4)
    upload.update_columns(created_at: 5.minutes.ago)

    Uploads::FinishJob.perform_now(upload.reload)
    assert_predicate upload.reload, :uploading?
    assert_equal 4, upload.received_bytes

    Uploads::Append.call(upload, io: StringIO.new("ef"), offset: 4, length: 2)
    assert_difference -> { Notification.count }, 1 do
      Uploads::FinishJob.perform_now(upload.reload)
    end
    notification = Notification.last
    assert_equal [ profiles(:alice), upload, "upload_ready", "Your file is up", "Ready to share or download" ],
                 [ notification.profile, notification.subject, notification.kind, wording_of(notification).title, wording_of(notification).detail ]
    assert_equal upload_path(upload), Notifications::Destination.new(notification).path
  ensure
    Uploads::Storage.delete(upload.key)
  end

  test "a check made again beside a slow one makes the file ready once" do
    upload = Uploads::Create.call(owner: profiles(:alice), name: "slow.bin", byte_size: 3).upload
    Uploads::Append.call(upload, io: StringIO.new("abc"), offset: 0, length: 3)
    slow, again = Upload.find(upload.id), Upload.find(upload.id)

    Uploads::FinishJob.perform_now(again)
    Uploads::FinishJob.perform_now(slow)

    assert_predicate upload.reload, :ready?
    assert_equal [ "uploaded" ], upload.upload_activities.pluck(:action)
  ensure
    Uploads::Storage.delete(upload.key)
  end

  private

  def upload_path(upload) = Rails.application.routes.url_helpers.upload_path(upload)
end
