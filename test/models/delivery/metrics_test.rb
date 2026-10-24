# frozen_string_literal: true

require "test_helper"

# Delivery::Metrics: DORA's four keys from production's deployment
# records, as Reports::Metric values over the last 30 days.
class Delivery::MetricsTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 10, 13, 12)

  def record(id, task, state, finished_at, sha: "s#{id}")
    Delivery::Github::Record.new(id: id, sha: sha, ref: sha, task: task, environment: "production", payload: {}, created_at: finished_at - 3.minutes,
                                 state: state, description: "", log_url: nil, finished_at: finished_at, inactive: false)
  end

  def commit(sha, committed_at)
    Delivery::Github::Commit.new(sha: sha, title: "c", author: "a", committed_at: committed_at, html_url: "u")
  end

  # Oldest first: a deploy 40 days ago, one 10 days ago that failed and was
  # deployed again 2 hours later, a success 5 days ago rolled back an hour
  # later, a rehearsal and a restart that don't count, a deploy in progress.
  def records
    [
      record(1, "deploy", "success", NOW - 40.days, sha: "s1"),
      record(2, "deploy", "failure", NOW - 10.days, sha: "s2"),
      record(3, "deploy", "success", NOW - 10.days + 2.hours, sha: "s2"),
      record(4, "deploy", "success", NOW - 5.days, sha: "s4"),
      record(5, "rollback", "success", NOW - 5.days + 1.hour, sha: "s2"),
      record(6, "restart", "success", NOW - 2.days, sha: "s2"),
      record(7, "deploy", nil, NOW, sha: "s7").with(finished_at: nil),
      Delivery::Github::Record.new(id: 8, sha: "x", ref: "x", task: "rehearse", environment: "staging", payload: {}, created_at: NOW - 1.day,
                                   state: "success", description: "", log_url: nil, finished_at: NOW - 1.day, inactive: false)
    ]
  end

  def metrics
    commits = { [ "s1", "s2" ] => [ commit("s2", NOW - 11.days) ], [ "s2", "s4" ] => [ commit("s3", NOW - 8.days), commit("s4", NOW - 6.days) ] }
    Delivery::Metrics.new(records: records.shuffle, now: NOW) { |from, to| commits.fetch([ from, to ], []) }
  end

  test "frequency counts successful deploys, releases and rollbacks, this period against the last, by week" do
    frequency = metrics.frequency
    assert_equal 3, frequency.value      # 3, 4 and the rollback
    assert_equal 1, frequency.previous   # 1, 40 days ago
    assert_equal :count, frequency.format
    assert_equal 13, frequency.series.size
    assert_equal 4, frequency.series.sum # the one 40 days ago too
    assert_equal :improving, frequency.trend
  end

  test "lead time is the median wait of the commits each successful change shipped" do
    lead = metrics.lead_time
    # s2 waited 1 day and 2 hours for deployment 3; s3 3 days and s4 1 day for deployment 4: median of 1.08, 3, 1 → 1.1 days.
    assert_in_delta 1.1, lead.value, 0.01
    assert_nil lead.previous
    assert_equal :days, lead.format
    assert_equal :lower_is_better, lead.polarity
  end

  test "a failed change is one that failed, or that a rollback followed within a day" do
    rate = metrics.failure_rate
    # Changes in the period: 2 (failed), 3, 4 (rolled back an hour later): 2 of 3.
    assert_equal 67, rate.value
    assert_equal 0, rate.previous
    assert_equal :percent, rate.format
    assert_equal :worsening, rate.trend
  end

  test "recovery is the median time from a failed change to the next success" do
    recovery = metrics.recovery_time
    # 2 → 3: 2 hours; 4 → the rollback: 1 hour. Median 1.5.
    assert_in_delta 1.5, recovery.value, 0.01
    assert_equal :hours, recovery.format
    assert_equal "1.5 hours", Statistics::Format.value(recovery.value, :hours)
    assert_equal "1 hour", Statistics::Format.value(1.0, :hours)
  end

  test "nothing recorded gives metrics without values, not zeros" do
    empty = Delivery::Metrics.new(records: [], now: NOW) { [] }.all
    assert_equal 0, empty[:frequency].value
    assert_nil empty[:lead_time].value
    assert_nil empty[:failure_rate].value
    assert_nil empty[:recovery_time].value
    assert_equal %i[frequency lead_time failure_rate recovery_time], empty.keys
  end

  test "a commit dated after its deployment (a fake, or a rewritten date) doesn't count" do
    metrics = Delivery::Metrics.new(records: records, now: NOW) { |_from, _to| [ commit("late", NOW + 1.day) ] }
    assert_nil metrics.lead_time.value
  end
end
