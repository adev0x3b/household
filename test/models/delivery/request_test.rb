# frozen_string_literal: true

require "test_helper"

class Delivery::RequestTest < ActiveSupport::TestCase
  SHA = "0123456789abcdef0123456789abcdef01234567"

  setup { @alice = profiles(:alice) }

  def a_run(id:, title: "", event: "workflow_dispatch", status: "completed", conclusion: "success", branch: "main", created_at: Time.current)
    Delivery::Github::Run.new(id: id, number: id, title: title, event: event, status: status, conclusion: conclusion, actor: "a", created_at: created_at,
                              updated_at: created_at, html_url: "https://github.com/example/household/actions/runs/#{id}", head_sha: SHA, head_branch: branch, workflow: "x")
  end

  test "the reason GitHub gets names who asked and the request's id, then their words" do
    request = Delivery::Request.create!(profile: @alice, action: :deploy, destination: "staging", reason: "trying it")
    assert_equal "alice from the app ##{request.id}: trying it", request.reason_for_github

    request = Delivery::Request.create!(profile: @alice, action: :restart, destination: "production")
    assert_equal "alice from the app ##{request.id}", request.reason_for_github
  end

  test "following a run records it, and its end" do
    request = Delivery::Request.create!(profile: @alice, action: :deploy, destination: "staging")
    assert_predicate request, :live?

    request.follow!(a_run(id: 9, status: "in_progress", conclusion: nil))
    assert_predicate request, :running?
    assert_equal [ 9, "https://github.com/example/household/actions/runs/9" ], [ request.run_id, request.run_url ]
    assert_nil request.finished_at

    request.follow!(a_run(id: 9, conclusion: "failure"))
    assert_predicate request, :failed?
    assert_predicate request, :ended?
    assert_equal "failure", request.summary
    assert request.finished_at
  end

  test "watching is what was pressed lately and hasn't ended" do
    old = Delivery::Request.create!(profile: @alice, action: :deploy, destination: "staging", created_at: 10.minutes.ago)
    fresh = Delivery::Request.create!(profile: @alice, action: :deploy, destination: "staging")
    done = Delivery::Request.create!(profile: @alice, action: :deploy, destination: "staging", status: :succeeded)

    assert_equal [ fresh ], Delivery::Request.watching.to_a
    assert_equal [ old, fresh ].sort, Delivery::Request.live.to_a.sort
    assert_not done.live?
    assert_raises(ActiveRecord::RecordInvalid) { Delivery::Request.create!(profile: @alice, action: :deploy, destination: "qa") }
  end

  test "a preview keeps its branch and whether it asked for fresh data" do
    request = Delivery::Request.create!(profile: @alice, action: :preview, destination: "dev", ref: "fix-the-bell", fresh: true)
    assert_predicate request, :preview?
    assert request.fresh
    assert_not Delivery::Request.create!(profile: @alice, action: :preview, destination: "dev", ref: "fix-the-bell").fresh
  end
end
