# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # The Actions API: the workflows' runs and jobs, and starting one.
    module Workflows
      # A workflow's runs, asked of the repository it is in.
      def workflow_runs(workflow: WORKFLOW, branch: nil, limit: 5)
        cached("runs/#{workflow}/#{branch}/#{limit.to_i}", LIVE_TTL) do
          call(get("/actions/workflows/#{workflow}/runs", per_page: limit.to_i, branch: branch, repository: repository_of(workflow)))
            .fetch("workflow_runs", []).map { |run| Run.from(run, workflow) }
        end
      end

      def run_jobs(run)
        cached("jobs/#{run.id.to_i}", LIVE_TTL) do
          call(get("/actions/runs/#{run.id.to_i}/jobs", per_page: 30, repository: repository_of(run.workflow))).fetch("jobs", []).map { |job| Job.from(job) }
        end
      end

      def active?(runs) = runs.any?(&:live?)

      # Starts deploy.yml on a destination: deploy (main's latest, or
      # `version`), restart, rollback to `version`, release (rehearsed on
      # staging first), preview (a `branch` on dev, on `fresh` data or not),
      # stop (dev only, until its next preview).
      # `reason` says who asked and why; it ends up in the run's name and the
      # deployment's record. The inputs are strings, as GitHub's "Run
      # workflow" form sends them (a boolean's "true").
      def dispatch(action:, reason:, destination: Deployment.destination, version: "", ref: "main", branch: "", fresh: false)
        raise ArgumentError, "unknown action #{action.inspect}" unless ACTIONS.include?(action.to_s)
        raise ArgumentError, "unknown destination #{destination.inspect}" unless Deployment::DESTINATIONS.include?(destination.to_s)
        raise ArgumentError, "a preview names its branch" if action.to_s == "preview" && branch.blank?
        raise ArgumentError, "only dev stops" if action.to_s == "stop" && destination.to_s != "dev"

        inputs = { destination: destination.to_s, action: action.to_s, reason: reason.to_s }
        inputs[:version] = version.to_s if version.present?
        inputs[:branch] = branch.to_s if branch.present?
        inputs[:fresh] = "true" if fresh
        call(post("/actions/workflows/#{WORKFLOW}/dispatches", ref: ref, inputs: inputs))
        true
      end

      # Starts ci.yml on a branch (main builds the image too; nothing deploys).
      def dispatch_ci(ref: "main")
        raise ArgumentError, "a branch is needed" if ref.blank?

        call(post("/actions/workflows/#{CI_WORKFLOW}/dispatches", ref: ref.to_s, repository: source))
        true
      end
    end
  end
end
