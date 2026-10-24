# frozen_string_literal: true

require "test_helper"

# Delivery::Github builds GitHub's requests and reads its answers; the
# network is one method (perform), swapped here. Each read's path, each
# write's body, the caching, and the token's expiry.
class Delivery::GithubTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body) do
    def [](_name) = nil
  end

  SHA = "0123456789abcdef0123456789abcdef01234567"
  OLD = "fedcba9876543210fedcba9876543210fedcba98"

  isolate_env "DEPLOY_DISPATCH_TOKEN", "KAMAL_DESTINATION"
  setup { ENV["DEPLOY_DISPATCH_TOKEN"] = "tok" }

  # Answers every request with one response (or per request, `with:` a
  # lambda given the request), and returns the requests sent.
  def answering(code = nil, body = "", with: nil)
    sent = []
    answer = with || ->(_request) { Response.new(code, body) }
    swapping(Delivery::Github, :perform, ->(request) { sent << request; answer.call(request) }) { yield }
    sent
  end

  test "dispatch posts the destination, the action and who asked to the Deploy workflow, with the token" do
    sent = answering("204") { assert Delivery::Github.dispatch(action: "restart", reason: "alice from the app", destination: "staging") }

    request = sent.sole
    assert_kind_of Net::HTTP::Post, request
    assert_equal "/repos/example/household/actions/workflows/deploy.yml/dispatches", request.path
    assert_equal "Bearer tok", request["Authorization"]
    assert_equal "application/vnd.github+json", request["Accept"]
    assert_equal "2022-11-28", request["X-GitHub-Api-Version"]
    assert_equal({ "ref" => "main", "inputs" => { "destination" => "staging", "action" => "restart", "reason" => "alice from the app" } }, JSON.parse(request.body))
  end

  test "a version goes into the inputs only when given; a release and a rollback are actions too" do
    sent = answering("204") do
      Delivery::Github.dispatch(action: "rollback", reason: "x", destination: "production", version: OLD)
      Delivery::Github.dispatch(action: "release", reason: "x", destination: "production")
    end

    assert_equal({ "destination" => "production", "action" => "rollback", "reason" => "x", "version" => OLD }, JSON.parse(sent.first.body)["inputs"])
    assert_equal %w[destination action reason], JSON.parse(sent.last.body)["inputs"].keys
  end

  test "the destination is the one answering, unless named" do
    ENV["KAMAL_DESTINATION"] = "production"
    sent = answering("204") { Delivery::Github.dispatch(action: "deploy", reason: "x") }
    assert_equal "production", JSON.parse(sent.sole.body).dig("inputs", "destination")
  end

  test "CI is started on a branch, and needs one" do
    sent = answering("204") { assert Delivery::Github.dispatch_ci(ref: "fix-the-bell") }

    assert_equal "/repos/example/household/actions/workflows/ci.yml/dispatches", sent.sole.path
    assert_equal({ "ref" => "fix-the-bell" }, JSON.parse(sent.sole.body))
    assert_raises(ArgumentError) { Delivery::Github.dispatch_ci(ref: " ") }
  end

  test "workflow_runs asks for the last few of a workflow (and a branch) and reads them" do
    body = { workflow_runs: [
      { id: 1, run_number: 12, display_title: "Deploy", event: "workflow_dispatch", status: "in_progress", conclusion: nil, head_sha: SHA, head_branch: "main",
        actor: { login: "alice" }, created_at: "2026-10-06T10:00:00Z", updated_at: "2026-10-06T10:01:00Z", html_url: "https://github.com/example/household/actions/runs/1" },
      { id: 2, run_number: 11, display_title: "CI", event: "workflow_run", status: "completed", conclusion: "success", head_sha: OLD, head_branch: "main",
        actor: { login: "bob" }, created_at: "2026-10-05T10:00:00Z", html_url: "https://github.com/example/household/actions/runs/2" }
    ] }.to_json

    runs = nil
    sent = answering("200", body) { runs = Delivery::Github.workflow_runs(limit: 2) }
    assert_kind_of Net::HTTP::Get, sent.sole
    assert_equal "/repos/example/household/actions/workflows/deploy.yml/runs?per_page=2", sent.sole.path
    assert_equal [ 12, 11 ], runs.map(&:number)
    assert_equal "alice", runs.first.actor
    assert_equal Time.utc(2026, 10, 6, 10), runs.first.created_at
    assert_equal SHA, runs.first.head_sha
    assert_equal "deploy.yml", runs.first.workflow
    assert_predicate runs.first, :live?
    assert_equal "in_progress", runs.first.state
    assert_equal "success", runs.last.state
    assert_predicate runs.last, :succeeded?
    assert Delivery::Github.active?(runs)
    assert_not Delivery::Github.active?([ runs.last ])

    sent = answering("200", body) { Delivery::Github.workflow_runs(workflow: "ci.yml", branch: "main", limit: 10) }
    assert_equal "/repos/example/household/actions/workflows/ci.yml/runs?branch=main&per_page=10", sent.sole.path
  end

  test "a run's jobs come with their steps" do
    body = { jobs: [ { id: 7, name: "staging / deploy staging", status: "in_progress", conclusion: nil, html_url: "u", started_at: "2026-10-06T10:00:00Z",
                       steps: [ { name: "Checkout code", status: "completed", conclusion: "success" }, { name: "Kamal deploy staging", status: "in_progress", conclusion: nil } ] } ] }.to_json

    jobs = nil
    run = Delivery::Github::Run.from({ "id" => 42, "path" => ".github/workflows/deploy.yml" })
    sent = answering("200", body) { jobs = Delivery::Github.run_jobs(run) }
    assert_equal "/repos/example/household/actions/runs/42/jobs?per_page=30", sent.sole.path
    assert_equal [ "success", "in_progress" ], jobs.sole.steps.map(&:state)
    assert_predicate jobs.sole, :live?
  end

  test "with a private pipeline, the code is asked of its own repository and the deploys of the pipeline's" do
    with_env("GITHUB_REPOSITORY" => "example/household-pipeline", "SOURCE_REPOSITORY" => "example/household") do
      sent = answering("200", { workflow_runs: [], jobs: [], sha: SHA, html_url: "u", commit: {} }.to_json) do
        Delivery::Github.workflow_runs(workflow: "ci.yml")
        Delivery::Github.workflow_runs
        Delivery::Github.commit(SHA)
        Delivery::Github.run_jobs(Delivery::Github::Run.from({ "id" => 1, "path" => ".github/workflows/ci.yml" }))
      end
      assert_equal(%w[household household-pipeline household household], sent.map { _1.path.split("/")[3] })

      sent = answering("204") do
        Delivery::Github.dispatch(action: "restart", reason: "alice", destination: "staging")
        Delivery::Github.dispatch_ci
      end
      assert_equal(%w[household-pipeline household], sent.map { _1.path.split("/")[3] })
    end
  end

  test "a commit, a comparison and a file are read where the console needs them" do
    answers = {
      "/repos/example/household/commits/main" => { sha: SHA, html_url: "u", author: { login: "alice" }, commit: { message: "Fix the bell\n\nMore", author: { name: "A", date: "2026-10-06T09:00:00Z" }, committer: { date: "2026-10-06T09:30:00Z" } } },
      "/repos/example/household/compare/#{OLD}...#{SHA}?per_page=250" => { status: "ahead", ahead_by: 1, behind_by: 0,
                                                                           commits: [ { sha: SHA, html_url: "u", commit: { message: "Fix the bell", author: { date: "2026-10-06T09:00:00Z" }, committer: { date: "2026-10-06T09:30:00Z" } } } ],
                                                                           files: [ { filename: "db/migrate/1_a.rb", status: "added" }, { filename: "app/models/event.rb", status: "modified" } ] },
      "/repos/example/household/contents/db/migrate/1_a.rb?ref=#{SHA}" => "class A < ActiveRecord::Migration[8.1]; end"
    }
    answer = ->(request) { found = answers.fetch(request.path); Response.new("200", found.is_a?(String) ? found : found.to_json) }
    sent = answering(with: answer) do
      commit = Delivery::Github.commit("main")
      assert_equal [ "Fix the bell", "alice", Time.utc(2026, 10, 6, 9, 30), "0123456" ], [ commit.title, commit.author, commit.committed_at, commit.short ]

      comparison = Delivery::Github.compare(OLD, SHA)
      assert_equal "ahead", comparison.status
      assert_equal [ SHA ], comparison.commits.map(&:sha)
      assert_equal [ "db/migrate/1_a.rb" ], comparison.added_files

      assert_equal "class A < ActiveRecord::Migration[8.1]; end", Delivery::Github.file("db/migrate/1_a.rb", SHA)
    end
    assert_equal "application/vnd.github.raw+json", sent.last["Accept"]
  end

  test "deployments come with their last status folded in, an inactive one keeping the state it hid" do
    answers = {
      "/repos/example/household/deployments?environment=staging&per_page=2" => [
        { id: 10, sha: SHA, ref: SHA, task: "deploy", environment: "staging", created_at: "2026-10-06T10:00:00Z",
          payload: { action: "deploy", destination: "staging", requested_by: "alice from the app #3", run_url: "r", running_before: OLD } },
        { id: 9, sha: OLD, ref: OLD, task: "rehearse", environment: "staging", created_at: "2026-10-05T10:00:00Z", payload: "{\"requested_by\":\"CI: x\"}" }
      ],
      "/repos/example/household/deployments/10/statuses?per_page=10" => [ { state: "in_progress", description: "deploy 0123456: in progress", log_url: "r", created_at: "2026-10-06T10:00:10Z" } ],
      "/repos/example/household/deployments/9/statuses?per_page=10" => [
        { state: "inactive", description: "", created_at: "2026-10-06T10:05:00Z" },
        { state: "success", description: "passed · migration 12 s · behind the page 77 s", target_url: "r9", created_at: "2026-10-05T10:04:00Z" },
        { state: "in_progress", description: "", created_at: "2026-10-05T10:00:10Z" }
      ]
    }
    answering(with: ->(request) { Response.new("200", answers.fetch(request.path).to_json) }) do
      live, done = Delivery::Github.records(environment: "staging", limit: 2)

      assert_predicate live, :live?
      assert_equal "in_progress", live.state
      assert_equal "alice from the app #3", live.requested_by
      assert_equal OLD, live.running_before
      assert_nil live.finished_at
      assert_not live.inactive

      assert_predicate done, :succeeded?
      assert done.inactive
      assert_equal "CI: x", done.requested_by
      assert_equal [ 12, 77 ], [ done.migration_seconds, done.downtime_seconds ]
      assert_equal Time.utc(2026, 10, 5, 10, 4), done.finished_at
      assert_equal "r9", done.log_url
    end
  end

  test "a deployment GitHub has no status for yet is live; one another tool made reads with no payload" do
    answers = {
      "/repos/example/household/deployments?environment=production&per_page=2" => [
        { id: 12, sha: SHA, ref: SHA, task: "deploy", environment: "production", created_at: "2026-10-07T10:00:00Z", payload: { requested_by: "alice from the app #4" } },
        { id: 11, sha: OLD, ref: "main", task: "deploy", environment: "production", created_at: "2026-10-06T10:00:00Z", payload: "made by hand" }
      ],
      "/repos/example/household/deployments/12/statuses?per_page=10" => [],
      "/repos/example/household/deployments/11/statuses?per_page=10" => [ { state: "failure", description: "", created_at: "2026-10-06T10:02:00Z" } ]
    }
    answering(with: ->(request) { Response.new("200", answers.fetch(request.path).to_json) }) do
      fresh, other = Delivery::Github.records(environment: "production", limit: 2)

      assert_predicate fresh, :live?, "just created: kamal.yml hasn't said anything yet"
      assert_equal [ nil, "", nil, nil ], [ fresh.state, fresh.description, fresh.log_url, fresh.finished_at ]
      assert_not fresh.inactive

      assert_predicate other, :failed?
      assert_equal({}, other.payload, "not JSON: nothing kamal.yml wrote")
      assert_nil other.requested_by
      assert_nil other.run_url
    end
  end

  test "the freeze is a variable: nil when unset, set then patched when it exists, deleted quietly when it isn't" do
    sent = answering(with: ->(request) { Response.new(request.path.include?("DEPLOY_FREEZE") ? "404" : "200", { message: "Not Found" }.to_json) }) do
      assert_nil Delivery::Github.variable("DEPLOY_FREEZE")
      assert_not Delivery::Github.frozen?
      assert Delivery::Github.delete_variable("DEPLOY_FREEZE")
    end
    assert_equal [ Net::HTTP::Get, Net::HTTP::Get, Net::HTTP::Delete ], sent.map(&:class)

    sent = answering(with: ->(request) { Response.new(request.is_a?(Net::HTTP::Post) ? "409" : "200", "") }) do
      assert Delivery::Github.set_variable("DEPLOY_FREEZE", "true")
    end
    assert_equal [ Net::HTTP::Post, Net::HTTP::Patch ], sent.map(&:class)
    assert_equal "/repos/example/household/actions/variables/DEPLOY_FREEZE", sent.last.path
    assert_equal({ "name" => "DEPLOY_FREEZE", "value" => "true" }, JSON.parse(sent.last.body))

    answering("200", { name: "DEPLOY_FREEZE", value: "true" }.to_json) { assert_predicate Delivery::Github, :frozen? }
  end

  test "check tries the five reads and names what the token can't" do
    refusing = ->(request) { request.path.include?("/deployments") ? Response.new("403", { message: "Resource not accessible by personal access token" }.to_json) : Response.new("200", "{}") }
    answering(with: refusing) do
      result = Delivery::Github.check
      assert_equal true, result[:actions]
      assert_equal true, result[:contents]
      assert_equal true, result[:variables]
      assert_equal true, result[:pull_requests]
      assert_equal "GitHub answered 403: Resource not accessible by personal access token", result[:deployments]
    end
  end

  test "reads are kept in the cache for their time; a write forgets what it changed" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    body = { workflow_runs: [] }.to_json

    sent = answering("200", body) { 3.times { Delivery::Github.workflow_runs(limit: 5) } }
    assert_equal 1, sent.size

    sent = answering("200", { name: "DEPLOY_FREEZE", value: "true" }.to_json) { 2.times { Delivery::Github.variable("DEPLOY_FREEZE") } }
    assert_equal 1, sent.size
    answering("204") { Delivery::Github.set_variable("DEPLOY_FREEZE", "false") }
    sent = answering("200", { name: "DEPLOY_FREEZE", value: "false" }.to_json) { assert_equal "false", Delivery::Github.variable("DEPLOY_FREEZE") }
    assert_equal 1, sent.size

    # A status that ended stays a day; one in progress, seconds.
    done = [ { state: "success", description: "deployed", created_at: "2026-10-05T10:04:00Z" } ].to_json
    answering("200", done) { Delivery::Github.deployment_statuses(9) }
    travel 1.hour do
      sent = answering("200", done) { Delivery::Github.deployment_statuses(9) }
      assert_empty sent
    end
    live = [ { state: "in_progress", description: "", created_at: "2026-10-05T10:04:00Z" } ].to_json
    answering("200", live) { Delivery::Github.deployment_statuses(10) }
    travel 1.minute do
      sent = answering("200", live) { Delivery::Github.deployment_statuses(10) }
      assert_equal 1, sent.size
    end
  ensure
    Rails.cache = ActiveSupport::Cache::NullStore.new
  end

  test "the token's expiry rides on an answer's headers and is kept for the settings page" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    response = Class.new(Response) { def [](name) = name == "github-authentication-token-expiration" ? "2026-12-01 10:00:00 UTC" : nil }.new("200", "[]")

    assert_nil Delivery::Github.token_expires_at
    # Beneath the client's own perform: the network every client shares.
    swapping(ApplicationClient, :perform, ->(_request, **) { response }) { Delivery::Github.branches }
    assert_equal Time.utc(2026, 12, 1, 10), Delivery::Github.token_expires_at
  ensure
    Rails.cache = ActiveSupport::Cache::NullStore.new
  end

  test "an expiry GitHub writes in a way that can't be read is reported, and the answer still counts" do
    response = Class.new(Response) { def [](name) = name == "github-authentication-token-expiration" ? "2026-13-45 10:00:00 UTC" : nil }.new("200", "[]")

    assert_error_reported(ArgumentError) do
      branches = swapping(ApplicationClient, :perform, ->(_request, **) { response }) { Delivery::Github.branches }
      assert_equal [], branches
    end
    assert_nil Delivery::Github.token_expires_at
  end

  test "GitHub's refusal is the error, with its message" do
    error = assert_raises(Delivery::Github::Error) do
      answering("422", { message: "Required input 'action' not provided" }.to_json) { Delivery::Github.dispatch(action: "deploy", reason: "x", destination: "production") }
    end
    assert_equal "GitHub answered 422: Required input 'action' not provided", error.message

    error = assert_raises(Delivery::Github::Error) { answering("404", "not json") { Delivery::Github.workflow_runs } }
    assert_equal "GitHub answered 404", error.message
  end

  test "no network is an error too, and an unknown action or destination, or a stop of anything but dev, never leaves" do
    swapping(Delivery::Github, :perform, ->(_request) { raise Delivery::Github::Error, "GitHub isn't answering (OpenTimeout)" }) do
      error = assert_raises(Delivery::Github::Error) { Delivery::Github.workflow_runs }
      assert_match(/isn't answering/, error.message)
    end

    swapping(Delivery::Github, :perform, ->(_request) { flunk "asked GitHub" }) do
      assert_raises(ArgumentError) { Delivery::Github.dispatch(action: "rm -rf", reason: "x", destination: "production") }
      assert_raises(ArgumentError) { Delivery::Github.dispatch(action: "deploy", reason: "x", destination: "qa") }
      assert_raises(ArgumentError) { Delivery::Github.dispatch(action: "deploy", reason: "x") } # development: no destination
      assert_raises(ArgumentError) { Delivery::Github.dispatch(action: "stop", reason: "x", destination: "production") }
    end
  end

  test "without the token nothing is asked" do
    ENV.delete("DEPLOY_DISPATCH_TOKEN")

    assert_not Delivery::Github.configured?
    assert_raises(Delivery::Github::Error) { Delivery::Github.dispatch(action: "deploy", reason: "x", destination: "production") }
    assert_raises(Delivery::Github::Error) { Delivery::Github.workflow_runs }
  end

  test "a self-hosted copy has no pipeline to ask, even holding a token" do
    with_env("HOUSEHOLD_IMAGE" => "ghcr.io/adev0x3b/household:2026.11.2@sha256:#{"ab" * 32}") do
      assert_not Delivery::Github.configured?
    end
    assert_predicate Delivery::Github, :configured?
  end

  test "a preview is dispatched with its branch, fresh only when asked; one without a branch never leaves" do
    sent = answering("204") do
      Delivery::Github.dispatch(action: "preview", reason: "x", destination: "dev", branch: "fix-the-bell", fresh: true)
      Delivery::Github.dispatch(action: "preview", reason: "x", destination: "dev", branch: "fix-the-bell")
    end

    assert_equal({ "destination" => "dev", "action" => "preview", "reason" => "x", "branch" => "fix-the-bell", "fresh" => "true" }, JSON.parse(sent.first.body)["inputs"])
    assert_equal %w[destination action reason branch], JSON.parse(sent.last.body)["inputs"].keys
    swapping(Delivery::Github, :perform, ->(_request) { flunk "asked GitHub" }) do
      assert_raises(ArgumentError) { Delivery::Github.dispatch(action: "preview", reason: "x", destination: "dev") }
    end
  end

  test "a branch's head is read, nil once the branch is gone; the branches are listed by name" do
    answers = {
      "/repos/example/household/branches/fix-the-bell" => Response.new("200", { name: "fix-the-bell", commit: { sha: SHA, html_url: "u", author: { login: "alice" },
                                                                                                                commit: { message: "Debounce the bell", author: { date: "2026-10-06T09:00:00Z" }, committer: { date: "2026-10-06T09:30:00Z" } } } }.to_json),
      "/repos/example/household/branches/gone" => Response.new("404", { message: "Branch not found" }.to_json),
      "/repos/example/household/branches?per_page=100" => Response.new("200", [ { name: "fix-the-bell" }, { name: "main" } ].to_json)
    }
    answering(with: ->(request) { answers.fetch(request.path) }) do
      head = Delivery::Github.branch("fix-the-bell")
      assert_equal [ SHA, "Debounce the bell", "alice" ], [ head.sha, head.title, head.author ]
      assert_nil Delivery::Github.branch("gone")
      assert_equal %w[fix-the-bell main], Delivery::Github.branches
    end
  end

  test "a branch's open pull request is read by its head, nil when there is none" do
    body = [ { number: 46, title: "Ring the bell", state: "open", draft: false, html_url: "u", user: { login: "alice" }, created_at: "2026-10-13T08:05:00Z",
               head: { ref: "fix-the-bell", sha: SHA }, base: { ref: "main" } } ].to_json
    pull = nil
    sent = answering("200", body) { pull = Delivery::Github.pull_request("fix-the-bell") }
    assert_equal "/repos/example/household/pulls?head=example%3Afix-the-bell&per_page=1&state=open", sent.sole.path
    assert_equal [ 46, "Ring the bell", SHA, "alice", Time.utc(2026, 10, 13, 8, 5) ], [ pull.number, pull.title, pull.head_sha, pull.author, pull.created_at ]
    assert_predicate pull, :open?

    answering("200", "[]") { assert_nil Delivery::Github.pull_request("nothing") }
  end

  test "a merge puts the method and the head sha, returns the merge commit and forgets what it changed" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write("delivery/github/commit/main", :stale)
    Rails.cache.write("delivery/github/branch/fix-the-bell", :stale)
    Rails.cache.write("delivery/github/pull/fix-the-bell", :stale)
    Rails.cache.write("delivery/github/runs/ci.yml/main/10", :stale)

    sent = answering("200", { merged: true, sha: OLD }.to_json) do
      assert_equal OLD, Delivery::Github.merge_pull_request(46, head_sha: SHA, branch: "fix-the-bell")
    end
    assert_kind_of Net::HTTP::Put, sent.sole
    assert_equal "/repos/example/household/pulls/46/merge", sent.sole.path
    assert_equal({ "merge_method" => "merge", "sha" => SHA }, JSON.parse(sent.sole.body))
    %w[commit/main branch/fix-the-bell pull/fix-the-bell runs/ci.yml/main/10].each { assert_nil Rails.cache.read("delivery/github/#{_1}"), _1 }

    error = assert_raises(Delivery::Github::Error) do
      answering("409", { message: "Head branch was modified. Review and try the merge again." }.to_json) { Delivery::Github.merge_pull_request(46, head_sha: SHA, branch: "b") }
    end
    assert_match(/409: Head branch was modified/, error.message)
  ensure
    Rails.cache = ActiveSupport::Cache::NullStore.new
  end
end
