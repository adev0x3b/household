# frozen_string_literal: true

require "test_helper"

class Uploads::SweepJobTest < ActiveSupport::TestCase
  test "the sweep takes abandoned uploads, bytes and all" do
    upload = Uploads::Create.call(owner: profiles(:alice), name: "half.bin", byte_size: 6).upload
    Uploads::Append.call(upload, io: StringIO.new("abc"), offset: 0, length: 3)
    upload.update_columns(updated_at: 2.days.ago)
    path = upload.path

    Uploads::SweepJob.perform_now

    assert_not Upload.exists?(upload.id)
    assert_not File.exist?(path)
    assert Upload.exists?(uploads(:backup).id), "a fresh one stays"
  end

  test "an abandoned upload that can't be removed is reported, and the sweep goes on" do
    stuck, half = %w[stuck.bin half.bin].map do |name|
      Uploads::Create.call(owner: profiles(:alice), name: name, byte_size: 6).upload.tap { _1.update_columns(updated_at: 2.days.ago) }
    end
    destroy = Uploads::Destroy.method(:call)
    refusing = ->(upload) { upload == stuck ? raise(Errno::EACCES, upload.path.to_s) : destroy.call(upload) }

    assert_error_reported(Errno::EACCES) do
      swapping(Uploads::Destroy, :call, refusing) { Uploads::SweepJob.perform_now }
    end

    assert Upload.exists?(stuck.id)
    assert_not Upload.exists?(half.id)
  end

  test "a check that stalled is made again, and given up on after a day, its owner told" do
    checking, stalled, given_up = [ 10.minutes, 2.hours, 25.hours ].map.with_index do |age, index|
      uploaded("file-#{index}.bin").tap { _1.update_columns(updated_at: age.ago) }
    end

    clear_enqueued_jobs # the checks their last chunks asked for

    assert_difference -> { Notification.count }, 1 do
      Uploads::SweepJob.perform_now
    end

    assert_enqueued_with job: Uploads::FinishJob, args: [ stalled ]
    assert_enqueued_jobs 1, only: Uploads::FinishJob
    assert_predicate checking.reload, :processing?
    assert_not Upload.exists?(given_up.id)
    assert_not File.exist?(given_up.path)

    notification = Notification.last
    assert_equal [ profiles(:alice), "upload_failed", "Your file couldn't be finished", "file-2.bin was removed: upload it again" ],
                 [ notification.profile, notification.kind, wording_of(notification).title, wording_of(notification).detail ]
    assert_equal Rails.application.routes.url_helpers.uploads_path, Notifications::Destination.new(notification).path
  ensure
    [ checking, stalled ].compact.each { Uploads::Storage.delete(_1.key) }
  end

  private

  # A whole file, waiting for its check.
  def uploaded(name)
    upload = Uploads::Create.call(owner: profiles(:alice), name: name, byte_size: 3).upload
    Uploads::Append.call(upload, io: StringIO.new("abc"), offset: 0, length: 3)
    upload.reload
  end
end
