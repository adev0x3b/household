# frozen_string_literal: true

module Delivery
  module Presses
    # CI by hand, on the branch given, main by default.
    class Ci < Base
      def self.kind = :ci
      def self.workflow = Github::CI_WORKFLOW

      # A dispatched CI run carries nothing of the request's, so it is the
      # first one on the branch that started after the press.
      def self.find_run(request)
        Github.workflow_runs(workflow: workflow, branch: request.ref, limit: 10)
          .find { _1.event == "workflow_dispatch" && _1.head_branch == request.ref && _1.created_at && _1.created_at >= request.created_at - 1.minute }
      end

      def icon = "fa-flask-vial"
      def destination = nil
      def ref = super.presence || Pipeline::BRANCH

      private

      def dispatch = Github.dispatch_ci(ref: ref)

      def request_attributes = { ref: ref }
    end
  end
end
