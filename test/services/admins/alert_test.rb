# frozen_string_literal: true

require "test_helper"

# What only the admin can fix reaches every admin's bell, once an hour
# at most for the same thing, and never fails what was failing already.
class Admins::AlertTest < ActiveJob::TestCase
  setup do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @alice = profiles(:alice).tap { _1.update!(role: :admin) }
    @bob = profiles(:bob).tap { _1.update!(role: :admin) }
  end

  teardown { Rails.cache = ActiveSupport::Cache::NullStore.new }

  test "every admin who has joined is told, and nobody else" do
    profiles(:bob).update!(invitation_token: "pending")

    perform_enqueued_jobs { Admins::Alert.call(:job_failed, name: "Uploads::FinishJob", detail: "Errno::ENOSPC: No space left on device") }

    told = Notification.where(kind: :job_failed)
    assert_equal [ @alice ], told.map(&:profile)
    wording = Notifications::Wording.new(told.sole)
    assert_equal [ "A job failed: Uploads::FinishJob", "Errno::ENOSPC: No space left on device" ], [ wording.title, wording.detail ]
  end

  test "the same thing rings once an hour; something else rings at once" do
    perform_enqueued_jobs do
      2.times { Admins::Alert.call(:error_reported, name: "IOError", detail: "the cable server went away") }
      Admins::Alert.call(:error_reported, name: "NoMethodError", detail: "undefined method 'name' for nil")
      Admins::Alert.call(:job_failed, name: "IOError", detail: "not an error kind, a job of that name")
    end
    assert_equal 3, @alice.notifications.count

    travel(Admins::Alert::EVERY + 1.second) do
      perform_enqueued_jobs { Admins::Alert.call(:error_reported, name: "IOError", detail: "the cable server went away") }
    end
    assert_equal 4, @alice.notifications.count
  end

  test "an alert that can't be sent is reported, and raises nothing into what called it" do
    swapping(Admins::AlertJob, :perform_later, ->(*) { raise ActiveRecord::ConnectionNotEstablished, "the queue is down" }) do
      assert_error_reported(ActiveRecord::ConnectionNotEstablished) do
        assert_nothing_raised { Admins::Alert.call(:error_reported, name: "IOError", detail: "the cable server went away") }
      end
    end
  end
end
