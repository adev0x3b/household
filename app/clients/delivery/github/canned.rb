# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # A made-up pipeline for a development server and the dev destination,
    # which have no token, so the console can be tried without a press ever
    # reaching GitHub. Its dates count back from now, so it always looks current.
    module Canned
      HEAD = "a1" * 20
      BRANCH = "try-the-console"
      BRANCH_HEAD = "e7" * 20
      PULL = 1

      Response = Struct.new(:code, :body) do
        # No headers: no token expiry to remember.
        def [](_name) = nil
      end

      module_function

      def on? = (Rails.env.development? || Deployment.destination == "dev") && ENV["DEPLOY_GITHUB_CANNED"].present?
      def frozen? = ENV["DEPLOY_GITHUB_CANNED"] == "frozen"

      def perform(request)
        path = request.uri.path.sub(%r{\A/repos/[^/]+/[^/]+}, "")
        query = Rack::Utils.parse_query(request.uri.query.to_s)
        # Writes change nothing. A merge still answers with a commit, since
        # the console records the merge commit it is given.
        return ok(merged: true, sha: HEAD) if request.method == "PUT" && path == "/pulls/#{PULL}/merge"
        return Response.new("204", "") unless request.method == "GET"

        case path
        when "/commits/main", "/commits/#{HEAD}" then ok(commit(HEAD, "Make the console readable on a phone", 2.hours.ago))
        when "/commits/#{BRANCH_HEAD}" then ok(commit(BRANCH_HEAD, "Try the console on dev", 1.hour.ago))
        when %r{\A/commits/(\h{40})\z} then ok(commit($1, "An earlier change", 1.day.ago))
        when "/branches" then ok([ { name: BRANCH, commit: { sha: BRANCH_HEAD } }, { name: "main", commit: { sha: HEAD } } ])
        when "/branches/#{BRANCH}" then ok(name: BRANCH, commit: commit(BRANCH_HEAD, "Try the console on dev", 1.hour.ago))
        when "/pulls" then ok(query["head"].to_s.end_with?(":#{BRANCH}") ? [ pull_request ] : [])
        when "/actions/workflows/ci.yml/runs" then ok(workflow_runs: [ ci_run(query["branch"] == BRANCH ? BRANCH_HEAD : HEAD, query["branch"]) ])
        when "/actions/workflows/deploy.yml/runs" then ok(workflow_runs: [ deploy_run ])
        when %r{\A/actions/runs/\d+/jobs\z} then ok(jobs: [ job ])
        when "/deployments" then ok(deployments(query["environment"], query["task"]))
        when %r{\A/deployments/\d+/statuses\z} then ok([ { state: "success", description: "deployed", created_at: 1.hour.ago } ])
        when "/compare/#{HEAD}...#{BRANCH_HEAD}" then ok(status: "ahead", ahead_by: 1, behind_by: 0, commits: [ commit(BRANCH_HEAD, "Try the console on dev", 1.hour.ago) ], files: [])
        when "/compare/#{BRANCH_HEAD}...#{HEAD}" then ok(status: "diverged", ahead_by: 1, behind_by: 1, commits: [], files: [])
        when %r{\A/compare/} then ok(status: "identical", ahead_by: 0, behind_by: 0, commits: [], files: [])
        when "/actions/variables/#{FREEZE}" then frozen? ? ok(name: FREEZE, value: "true") : missing
        when "/actions/variables/#{FREEZE_NOTE}" then frozen? ? ok(name: FREEZE_NOTE, value: "alex · #{I18n.l(Date.current)} · trying the freeze") : missing
        else missing
        end
      end

      def ok(answer) = Response.new("200", answer.to_json)
      def missing = Response.new("404", { message: "Not Found" }.to_json)

      def commit(sha, title, at)
        { sha: sha, html_url: Deployment.github_url("commit", sha), author: { login: "alex" },
          commit: { message: title, author: { name: "alex", date: at }, committer: { name: "alex", date: at } } }
      end

      def pull_request
        { number: PULL, title: "Try the console on dev", state: "open", draft: false, html_url: Deployment.github_url("pull", PULL),
          user: { login: "alex" }, created_at: 1.hour.ago, head: { ref: BRANCH, sha: BRANCH_HEAD }, base: { ref: "main" } }
      end

      def ci_run(sha, branch)
        run(id: 1, title: "CI", event: "push", sha: sha, branch: branch || "main", at: 90.minutes.ago)
      end

      def deploy_run
        run(id: 2, title: "deploy staging — alex from the app #1: trying the console", event: "workflow_dispatch", sha: HEAD, branch: "main", at: 1.hour.ago)
      end

      def run(id:, title:, event:, sha:, branch:, at:)
        { id: id, run_number: id, display_title: title, event: event, status: "completed", conclusion: "success", actor: { login: "alex" },
          created_at: at, updated_at: at, html_url: Deployment.github_url("actions", "runs", id), head_sha: sha, head_branch: branch }
      end

      # One job that built the image, so main's head reads as built.
      def job
        { id: 1, name: "image", status: "completed", conclusion: "success", started_at: 90.minutes.ago, completed_at: 80.minutes.ago,
          html_url: Deployment.github_url("actions", "runs", 1, "job", 1), steps: [ { name: "Build", status: "completed", conclusion: "success" } ] }
      end

      # One succeeded deployment per destination: main's head on the
      # mainline, the branch on dev. Nothing was ever rehearsed.
      def deployments(environment, task)
        return [] if task == "rehearse"

        all = Deployment::DESTINATIONS.map.with_index(1) do |destination, id|
          dev = destination == "dev"
          { id: id, sha: dev ? BRANCH_HEAD : HEAD, ref: dev ? BRANCH_HEAD : HEAD, task: dev ? "preview" : "deploy", environment: destination,
            created_at: (dev ? 1 : id).hours.ago,
            payload: { requested_by: "alex from the app ##{id}: trying the console", run_url: Deployment.github_url("actions", "runs", 2),
                       **(dev ? { branch: BRANCH, fresh: true } : {}) } }
        end
        environment ? all.select { _1[:environment] == environment } : all
      end
    end
  end
end
