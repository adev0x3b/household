# frozen_string_literal: true

# GitHub answered from test/fixtures/files/github/, in place of
# Delivery::Github.perform (CannedPipeline#canned swaps it in). The files
# draw one pipeline: main's head passed CI with its image built, staging
# runs it after a rehearsal that passed, the demo runs it too, production
# runs three commits behind and one of them needs the app stopped, a
# deploy of staging is in progress; dev runs the branch fix-the-bell on
# fresh data, the branch has moved on by a commit since, and its pull
# request #46 passed CI on that head. Every write answers 204 and changes
# nothing, but a merge, which answers main's head as the merge commit.
module GithubFixtures
  DIR = Rails.root.join("test/fixtures/files/github")
  HEAD = "a1" * 20
  PRODUCTION = "b2" * 20
  OLDER = "c3" * 20
  OLDEST = "d4" * 20
  # What dev runs, the branch it is from, and the branch's head now.
  DEV = "e7" * 20
  BRANCH = "fix-the-bell"
  BRANCH_HEAD = "f8" * 20
  PULL = 46
  HELD_MIGRATION = "db/migrate/20261014120000_fold_event_shares.rb"

  Response = Struct.new(:code, :body) do
    # No headers: no token expiry to remember.
    def [](_name) = nil
  end

  module_function

  # frozen: the pipeline with DEPLOY_FREEZE set, and its note.
  def perform(request, frozen: false)
    path = request.uri.path.sub(%r{\A/repos/[^/]+/[^/]+}, "")
    query = Rack::Utils.parse_query(request.uri.query.to_s)
    return Response.new("200", { merged: true, sha: HEAD }.to_json) if request.method == "PUT" && path == "/pulls/#{PULL}/merge"
    return Response.new("204", "") unless request.method == "GET"

    case path
    when "/commits/main", "/commits/#{HEAD}" then json("commit_main")
    when "/commits/#{PRODUCTION}" then json("commit_production")
    when "/commits/#{DEV}" then json("commit_dev")
    when "/commits/#{BRANCH_HEAD}" then json("commit_branch")
    when %r{\A/commits/(\h{40})\z} then commit($1)
    when "/branches" then json("branches")
    when "/branches/#{BRANCH}" then json("branch")
    when "/pulls" then query["head"] == "#{Deployment.source_repository.split("/").first}:#{BRANCH}" ? json("pull_request") : Response.new("200", "[]")
    when "/actions/workflows/ci.yml/runs" then query["branch"] == BRANCH ? json("ci_runs_branch") : json("ci_runs")
    when "/actions/workflows/deploy.yml/runs" then json("deploy_runs")
    when %r{\A/actions/runs/(\d+)/jobs\z} then json("jobs_#{$1}", "jobs_done")
    when "/deployments" then json(query["task"] == "rehearse" ? "deployments_rehearse" : "deployments_#{query["environment"] || "all"}")
    when %r{\A/deployments/(\d+)/statuses\z} then json("statuses_#{$1}", "statuses_success")
    when "/compare/#{DEV}...#{BRANCH_HEAD}", "/compare/#{HEAD}...#{BRANCH_HEAD}" then json("compare_branch")
    when "/compare/#{DEV}...#{HEAD}", "/compare/#{BRANCH_HEAD}...#{HEAD}" then json("compare_diverged")
    when %r{\A/compare/} then json("compare")
    when %r{\A/contents/} then raw("migration_held.rb")
    when "/actions/variables/#{Delivery::Github::FREEZE}" then frozen ? json("variable_freeze") : missing
    when "/actions/variables/#{Delivery::Github::FREEZE_NOTE}" then frozen ? json("variable_freeze_note") : missing
    when "/actions/variables" then json("variables")
    else missing
    end
  end

  def json(name, fallback = nil)
    file = DIR.join("#{name}.json")
    file = DIR.join("#{fallback}.json") if !file.exist? && fallback
    file.exist? ? Response.new("200", file.read) : missing
  end

  def raw(name) = Response.new("200", DIR.join(name).read)

  # Any other commit: production's, under the sha asked for.
  def commit(sha) = Response.new("200", DIR.join("commit_production.json").read.gsub(PRODUCTION, sha))
  def missing = Response.new("404", { message: "Not Found" }.to_json)
end
