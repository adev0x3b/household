# frozen_string_literal: true

require "test_helper"

# The admin's page of mail, read: whether mail goes out, what went against
# the budgets, what waits and what couldn't go out.
class Emails::OverviewTest < ActiveSupport::TestCase
  setup { Rails.cache = ActiveSupport::Cache::MemoryStore.new }
  teardown { Rails.cache = ActiveSupport::Cache::NullStore.new }

  def row(profile, status, at:, **columns)
    OutgoingEmail.create!(profile: profile, kind: :test_mail, status: status, not_before: at, expires_at: at + 15.minutes, **columns)
  end

  test "says whether mail goes out, and what stops it otherwise" do
    assert_equal :unconfigured, Emails::Overview.new.state
    assert_equal :off, with_relay("OUTGOING_MAIL" => "off") { Emails::Overview.new.state }

    with_relay do
      assert_equal :sending, Emails::Overview.new.state
      Emails::RelayPause.start(Emails::Relay::Misconfigured.new(:login))
      overview = Emails::Overview.new
      assert_equal :paused, overview.state
      assert_predicate overview, :enabled?
      assert_equal :login, overview.pause.problem
    end
  end

  test "counts what was taken to go in the rolling hour and day, refused too, and lists what waits soonest first and what failed lately newest first" do
    row(profiles(:alice), :sent, at: 30.minutes.ago, claimed_at: 30.minutes.ago, message_id: "a@household.example")
    row(profiles(:bob), :sent, at: 3.hours.ago, claimed_at: 3.hours.ago, message_id: "b@household.example")
    later = row(profiles(:bob), :queued, at: 10.minutes.from_now)
    sooner = row(profiles(:carol), :queued, at: 1.minute.ago)
    sending = row(profiles(:carol), :sending, at: 2.minutes.ago, claimed_at: 1.minute.ago, message_id: "c@household.example")
    failed_lately = row(profiles(:outsider), :failed, at: 2.days.ago, updated_at: 2.days.ago)
    failed_last = row(profiles(:alice), :failed, at: 1.hour.ago, updated_at: 1.hour.ago, claimed_at: 55.minutes.ago, message_id: "d@household.example")
    row(profiles(:alice), :failed, at: 40.days.ago, updated_at: 40.days.ago)
    row(profiles(:alice), :dropped, at: 1.hour.ago)

    overview = Emails::Overview.new
    assert_equal [ 3, 4 ], [ overview.used_this_hour, overview.used_today ]
    assert_equal [ 6, 40 ], [ overview.hourly_budget, overview.daily_budget ]
    assert_equal [ sending, sooner, later ], overview.waiting
    assert_equal 3, overview.waiting_count
    assert_equal [ failed_last, failed_lately ], overview.failed
    assert_equal 2, overview.failed_count
  end
end
