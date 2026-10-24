# frozen_string_literal: true

require "test_helper"

# Every job's one policy: what passes is tried again, a record gone is let
# go, and what can't be done twice fails instead.
class ApplicationJobTest < ActiveJob::TestCase
  class Flaky < ApplicationJob
    def perform = raise ActiveRecord::Deadlocked
  end

  class Once < ApplicationJob
    runs_once
    def perform = raise ActiveRecord::Deadlocked
  end

  class Gone < ApplicationJob
    def perform(unit) = raise "never reached for #{unit.id}"
  end

  class Broken < ApplicationJob
    def perform = raise Errno::ENOSPC
  end

  test "a deadlock or a lost connection is tried again, later" do
    assert_enqueued_with(job: Flaky) { Flaky.perform_now }
  end

  test "a job that can't be done twice fails instead, recorded" do
    assert_raises(ActiveRecord::Deadlocked) { Once.perform_now }
    assert_no_enqueued_jobs only: Once
  end

  test "a record deleted before the job ran: nothing left to do" do
    unit = Unit.create!(household: households(:example), name: "drop")
    Gone.perform_later(unit)
    unit.delete

    assert_nothing_raised { perform_enqueued_jobs only: Gone }
  end

  test "the assistant's reply never runs twice: a deadlock fails it instead of answering again later" do
    chat = assistant_chat(profiles(:alice))
    chat.claim_reply!
    claimed_at = chat.replying_since
    swapping(chat, :replying_since, -> { raise ActiveRecord::Deadlocked }) do
      assert_raises(ActiveRecord::Deadlocked) { Assistant::ReplyJob.perform_now(chat, claimed_at) }
    end
    assert_no_enqueued_jobs only: Assistant::ReplyJob
  end

  test "a job that fails for good tells the admin, by its name and its error" do
    alerts = []
    swapping(Admins::Alert, :call, ->(kind, **data) { alerts << [ kind, data ] }) do
      assert_raises(Errno::ENOSPC) { Broken.perform_now }
      assert_raises(ActiveRecord::Deadlocked) { Once.perform_now }
      Flaky.perform_now
    end

    assert_equal [ [ :job_failed, { name: "ApplicationJobTest::Broken", detail: "Errno::ENOSPC: No space left on device" } ],
                   [ :job_failed, { name: "ApplicationJobTest::Once", detail: "ActiveRecord::Deadlocked: ActiveRecord::Deadlocked" } ] ],
                 alerts, "a job tried again later hasn't failed yet"
  end

  test "neither a job let go on purpose nor a failing alert tells the admin" do
    unit = Unit.create!(household: households(:example), name: "drop")
    Gone.perform_later(unit)
    unit.delete

    swapping(Admins::Alert, :call, ->(*) { flunk "the admin was alerted" }) do
      perform_enqueued_jobs only: Gone
      swapping(Notifications::Deliver, :call, ->(**) { raise Errno::ENOSPC }) do
        profiles(:alice).update!(role: :admin)
        assert_raises(Errno::ENOSPC) { Admins::AlertJob.perform_now("job_failed", { "name" => "Uploads::FinishJob" }) }
      end
    end
  end
end
