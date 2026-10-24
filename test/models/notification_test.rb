# frozen_string_literal: true

require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    @bob = profiles(:bob)
    @recipe = recipes(:roast_chicken)
  end

  test "it knows how it ended from its kind" do
    assert_predicate Notification.new(kind: :deploy_failed), :failure?
    assert_predicate Notification.new(kind: :link_accepted), :success?
    assert_not Notification.new(kind: :reminder_due).failure?
    assert_not Notification.new(kind: :reminder_due).success?
  end

  test "something due, something that failed and a deploy that went through may wake a phone" do
    assert_predicate Notification.new(kind: :reminder_due), :urgent?
    assert_predicate Notification.new(kind: :deploy_failed), :urgent?
    assert_predicate Notification.new(kind: :deploy_succeeded), :urgent?
    assert_not Notification.new(kind: :shared).urgent?
  end

  test "an alert to the admin is news of a failure, which wakes their phone" do
    %i[error_reported job_failed].each do |kind|
      alert = Notification.new(kind: kind)
      assert_predicate alert, :admin_alert?
      assert_predicate alert, :failure?
      assert_predicate alert, :urgent?
    end
    assert_not Notification.new(kind: :deploy_failed).admin_alert?
  end

  test "reading it once keeps the first time" do
    notification = Notification.create!(profile: @bob, kind: :shared, subject: @recipe)
    assert_predicate notification, :unread?

    notification.mark_read!
    read_at = notification.read_at
    notification.mark_read!

    assert_equal read_at, notification.read_at
    assert_not_includes Notification.unread, notification
  end

  test "those older than one come after it in the list's order, even made in the same moment" do
    at = 1.hour.ago
    first, second, third = Array.new(3) { Notification.create!(profile: @bob, kind: :shared, subject: @recipe, created_at: at) }
    yesterday = Notification.create!(profile: @bob, kind: :shared, subject: @recipe, created_at: 1.day.ago)

    these = Notification.where(id: [ first, second, third, yesterday ]).recent_first

    assert_equal [ third, second, first, yesterday ], these.to_a
    assert_equal [ first, yesterday ], these.older_than(second).to_a
  end
end
