# frozen_string_literal: true

require "test_helper"

# Deployment::ReleaseNoticeJob tells every member about a release with
# downtime: once when it starts, once when it ended — on production only.
class Deployment::ReleaseNoticeJobTest < ActiveJob::TestCase
  SHA = "0123456789abcdef0123456789abcdef01234567"

  isolate_env "DEPLOY_DISPATCH_TOKEN", "KAMAL_DESTINATION"

  setup do
    ENV.update("DEPLOY_DISPATCH_TOKEN" => "tok", "KAMAL_DESTINATION" => "production")
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = ActiveSupport::Cache::NullStore.new }

  def a_run(id:, title:, status:, conclusion: nil, updated_at: Time.current, event: "workflow_dispatch")
    Delivery::Github::Run.new(id: id, number: id, title: title, event: event, status: status, conclusion: conclusion, actor: "a", created_at: updated_at,
                              updated_at: updated_at, html_url: "https://github.com/example/household/actions/runs/#{id}", head_sha: SHA, head_branch: "main", workflow: "deploy.yml")
  end

  test "a release in progress is told to every joined member once, and its end once more" do
    live = [ a_run(id: 1, title: "release production at #{SHA} — alice from the app #4", status: "in_progress"),
             a_run(id: 2, title: "deploy staging — alice", status: "in_progress") ]
    joined = Profile.joined.count
    assert_operator joined, :>, 1

    swapping(Delivery::Github, :workflow_runs, ->(**) { live }) do
      assert_difference(-> { Notification.release_starting.count }, joined) { Deployment::ReleaseNoticeJob.perform_now }
      assert_no_difference(-> { Notification.count }) { Deployment::ReleaseNoticeJob.perform_now }
    end
    notification = Notification.release_starting.first
    assert_equal "Household is about to update: a minute of downtime", wording_of(notification).title
    assert_nil Notifications::Destination.new(notification).path if notification.profile.user?
    assert_equal "0123456", notification.data["version"]

    ended = [ a_run(id: 1, title: "release production at #{SHA} — alice from the app #4", status: "completed", conclusion: "success") ]
    swapping(Delivery::Github, :workflow_runs, ->(**) { ended }) do
      assert_difference(-> { Notification.release_finished.count }, joined) { Deployment::ReleaseNoticeJob.perform_now }
      assert_no_difference(-> { Notification.count }) { Deployment::ReleaseNoticeJob.perform_now }
    end

    undone = [ a_run(id: 3, title: "release production — alice", status: "completed", conclusion: "failure") ]
    swapping(Delivery::Github, :workflow_runs, ->(**) { undone }) do
      assert_difference(-> { Notification.release_undone.count }, joined) { Deployment::ReleaseNoticeJob.perform_now }
    end
    assert_equal :alert, wording_of(Notification.release_undone.first).toast_kind
  end

  test "an old ending, a run by CI, and anything but production are left alone" do
    old = [ a_run(id: 5, title: "release production — x", status: "completed", conclusion: "success", updated_at: 3.hours.ago),
            a_run(id: 6, title: "Deploy release production", status: "in_progress", event: "workflow_run") ]
    swapping(Delivery::Github, :workflow_runs, ->(**) { old }) do
      assert_no_difference(-> { Notification.count }) { Deployment::ReleaseNoticeJob.perform_now }
    end

    ENV["KAMAL_DESTINATION"] = "staging"
    swapping(Delivery::Github, :workflow_runs, ->(**) { flunk "asked GitHub" }) { Deployment::ReleaseNoticeJob.perform_now }
  end

  test "GitHub being away is reported and nobody is told anything" do
    away = ->(**) { raise Delivery::Github::Error, "GitHub isn't answering (OpenTimeout)" }

    assert_no_difference(-> { Notification.count }) do
      assert_error_reported(Delivery::Github::Error) do
        swapping(Delivery::Github, :workflow_runs, away) { Deployment::ReleaseNoticeJob.perform_now }
      end
    end
  end
end
