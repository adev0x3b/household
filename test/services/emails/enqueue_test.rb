# frozen_string_literal: true

require "test_helper"

# A mail to one person, in the outbox until its kind stops being worth
# sending, and a drain started once what queued it is committed.
class Emails::EnqueueTest < ActiveSupport::TestCase
  test "queues the mail for now, for as long as its kind waits, and starts a drain" do
    assert_enqueued_with(job: Emails::DrainJob) { Emails::Enqueue.call(profiles(:alice), :test_mail) }
    row = OutgoingEmail.sole

    assert_predicate row, :queued?
    assert_equal profiles(:alice), row.profile
    assert_in_delta Time.current, row.not_before, 1.second
    assert_equal Emails::Kinds::TestMail.waits_at_most, row.expires_at - row.not_before
  end

  test "the drain starts only once the transaction that queued the mail commits, and never when it is rolled back" do
    ActiveRecord::Base.transaction do
      Emails::Enqueue.call(profiles(:alice), :test_mail)
      assert_no_enqueued_jobs(only: Emails::DrainJob)
    end
    assert_enqueued_jobs 1, only: Emails::DrainJob

    clear_enqueued_jobs
    ActiveRecord::Base.transaction do
      Emails::Enqueue.call(profiles(:alice), :test_mail)
      raise ActiveRecord::Rollback
    end
    assert_no_enqueued_jobs(only: Emails::DrainJob)
  end

  test "a reminder waits a minute for the drain that gathers what fell due with it, and no longer than its latest" do
    freeze_time
    due = 20.minutes.from_now

    assert_no_enqueued_jobs(only: Emails::DrainJob) { Emails::Enqueue.call(profiles(:alice), :reminder, data: { "event_reminder_id" => 1 }, latest: due) }

    row = OutgoingEmail.sole
    assert_equal [ Emails::Enqueue::GATHER.from_now, due ], [ row.not_before, row.expires_at ]
  end

  test "a kind of mail the outbox doesn't know is refused" do
    assert_raises(ArgumentError) { Emails::Enqueue.call(profiles(:alice), :newsletter) }
    assert_not OutgoingEmail.exists?
  end
end
