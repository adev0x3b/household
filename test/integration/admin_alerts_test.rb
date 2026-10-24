# frozen_string_literal: true

require "test_helper"

# An error reported anywhere reaches the admin's bell the first time
# Solid Errors sees its kind, through Solid Errors' own subscriber and its
# events (config/initializers/admin_alerts.rb).
class AdminAlertsTest < ActiveJob::TestCase
  setup do
    # The errors' tables, in this test's transaction only (outside tests
    # they have a database of their own).
    ActiveRecord::Schema.verbose = false
    load Rails.root.join("db/errors_schema.rb")
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @admin = profiles(:alice).tap { _1.update!(role: :admin) }
  end

  teardown { Rails.cache = ActiveSupport::Cache::NullStore.new }

  test "a new kind of error is told once, and again when it comes back after being resolved" do
    2.times { report(IOError.new("the cable server went away")) }
    assert_equal [ "New error: IOError" ], titles

    SolidErrors::Error.sole.update!(resolved_at: Time.current)
    travel(Admins::Alert::EVERY + 1.second) { report(IOError.new("the cable server went away")) }
    assert_equal [ "New error: IOError" ] * 2, titles
  end

  test "an error handled and gone on from is told like one that wasn't" do
    report(Errno::ECONNREFUSED.new("the model's server"), handled: true, severity: :warning)

    assert_equal [ "New error: Errno::ECONNREFUSED" ], titles
    assert_equal "Connection refused - the model's server", @admin.notifications.sole.data["detail"]
  end

  test "a job's failure, which the job has told already, isn't told again as an error" do
    report(Errno::ENOSPC.new, source: "application.solid_queue")

    assert_predicate SolidErrors::Error, :exists?
    assert_empty titles
  end

  private

  def report(error, handled: false, severity: :error, source: "application")
    perform_enqueued_jobs { SolidErrors::Subscriber.new.report(error, handled: handled, severity: severity, context: {}, source: source) }
  end

  def titles = @admin.notifications.recent_first.map { Notifications::Wording.new(_1).title }
end
