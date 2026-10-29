# frozen_string_literal: true

require "test_helper"

# The drain runs on the jobs' worker, one at a time: one that finds another
# running leaves it the work.
class Emails::DrainJobTest < ActiveSupport::TestCase
  test "drains the outbox" do
    drained = 0
    swapping(Emails::Drain, :call, -> { drained += 1 }) { Emails::DrainJob.perform_now }

    assert_equal 1, drained
  end

  test "one at a time, the next given up rather than queued behind" do
    assert_equal [ 1, :discard ], [ Emails::DrainJob.concurrency_limit, Emails::DrainJob.concurrency_on_conflict ]
  end
end
