# frozen_string_literal: true

module Delivery
  module Presses
    # The branch dev runs into main, through its pull request, once CI
    # passed on its head. Nothing to press until then.
    class Merge < Base
      def self.kind = :merge
      def self.action = "merge_branch"
      def self.workflow = Github::CI_WORKFLOW

      # A merge is followed to CI on main for its merge commit, not to the
      # Deploy run after it: that one succeeds even when it skipped staging.
      def self.find_run(request)
        return if request.version.blank?

        Github.workflow_runs(workflow: workflow, branch: Pipeline::BRANCH, limit: 10).find { _1.head_sha == request.version }
      end

      def icon = "fa-code-merge"
      def destination = nil
      def ref = pipeline.dev.branch
      def state = pipeline.merge_state(pipeline.dev)
      def blocked? = state != :ready

      private

      # Merged only at the head the console showed: GitHub refuses it
      # otherwise. The merge commit is kept, since that is what CI then runs.
      def dispatch
        pull = pipeline.pull_request(pipeline.dev)
        @request.update!(version: Github.merge_pull_request(pull.number, head_sha: pull.head_sha, branch: ref))
      end

      def request_attributes = { ref: ref }

      def check
        super
        return unless blocked?

        errors.add(:base, ref.blank? ? :no_branch : :"merge_#{state}")
      end
    end
  end
end
