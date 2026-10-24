# frozen_string_literal: true

require "test_helper"

# Delivery::WatchJob follows a request until its run ends, then tells
# whoever pressed.
class Delivery::WatchJobTest < ActiveJob::TestCase
  SHA = "0123456789abcdef0123456789abcdef01234567"

  setup do
    @alice = profiles(:alice).tap { _1.update!(role: :admin) }
    @request = Delivery::Request.create!(profile: @alice, action: :deploy, destination: "staging", version: SHA, reason: "trying")
  end

  def a_run(status:, conclusion: nil)
    Delivery::Github::Run.new(id: 77, number: 77, title: "deploy staging — alice from the app ##{@request.id}: trying", event: "workflow_dispatch", status: status,
                              conclusion: conclusion, actor: "a", created_at: Time.current, updated_at: Time.current,
                              html_url: "https://github.com/example/household/actions/runs/77", head_sha: SHA, head_branch: "main", workflow: "deploy.yml")
  end

  test "looks again while the run isn't listed, records it once it is, and tells the admin when it ends" do
    swapping(Delivery::Github, :workflow_runs, ->(**) { [] }) { Delivery::WatchJob.perform_now(@request.id) }
    assert_predicate @request.reload, :requested?
    assert_enqueued_with(job: Delivery::WatchJob, args: [ @request.id ])

    listed = [ a_run(status: "in_progress") ]
    swapping(Delivery::Github, :workflow_runs, ->(**) { listed }) { Delivery::WatchJob.perform_now(@request.id) }
    assert_predicate @request.reload, :running?
    assert_equal 77, @request.run_id

    listed = [ a_run(status: "completed", conclusion: "success") ]
    swapping(Delivery::Github, :workflow_runs, ->(**) { listed }) do
      assert_difference -> { @alice.notifications.count }, 1 do
        Delivery::WatchJob.perform_now(@request.id)
      end
    end
    assert_predicate @request.reload, :succeeded?
    notified = @alice.notifications.recent_first.first
    assert_predicate notified, :deploy_succeeded?
    assert_equal "The deploy to Staging succeeded", wording_of(notified).title
    assert_equal "success", wording_of(notified).detail
    assert_equal "#{Rails.configuration.x.mount_path}/admin/deployment", Notifications::Destination.new(notified).path
  end

  test "a failed run is told as a failure, with the state as the detail" do
    listed = [ a_run(status: "completed", conclusion: "failure") ]
    swapping(Delivery::Github, :workflow_runs, ->(**) { listed }) { Delivery::WatchJob.perform_now(@request.id) }

    assert_predicate @request.reload, :failed?
    notified = @alice.notifications.recent_first.first
    assert_predicate notified, :deploy_failed?
    assert_equal :alert, wording_of(notified).toast_kind
  end

  test "a run that never shows up is given up on after a while, and said so" do
    @request.update!(created_at: 2.hours.ago)

    swapping(Delivery::Github, :workflow_runs, ->(**) { [] }) { Delivery::WatchJob.perform_now(@request.id) }

    assert_predicate @request.reload, :lost?
    notified = @alice.notifications.recent_first.first
    assert_equal "lost", notified.data["outcome"]
    assert_match(/never showed up/, wording_of(notified).detail)
    assert_no_enqueued_jobs only: Delivery::WatchJob
  end

  test "GitHub being away is tried again later; an ended or missing request is left alone" do
    away = ->(**) { raise Delivery::Github::Error, "GitHub isn't answering (OpenTimeout)" }
    assert_error_reported(Delivery::Github::Error) do
      swapping(Delivery::Github, :workflow_runs, away) { Delivery::WatchJob.perform_now(@request.id) }
    end
    assert_enqueued_with(job: Delivery::WatchJob, args: [ @request.id ])

    @request.update!(status: :succeeded)
    swapping(Delivery::Github, :workflow_runs, ->(**) { flunk "asked" }) do
      Delivery::WatchJob.perform_now(@request.id)
      Delivery::WatchJob.perform_now(-1)
    end
  end
end
