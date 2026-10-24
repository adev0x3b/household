# frozen_string_literal: true

module Delivery
  module Presses
    # A version that needs the app stopped, rehearsed on staging and then
    # put on production behind the maintenance page: main's head, or the
    # version given. The password, the version typed back, and a reason.
    class Release < Base
      def self.kind = :release
      def icon = "fa-hand"
      def destination = "production"
      def danger? = true
      def reason_required? = true
      def gated? = true
      def version = super.presence || pipeline.head.sha

      # The migrations the version adds over what production runs that need the app stopped.
      def held = (@held ||= pipeline.held_between(environment.version, version))
      # The commits production would gain.
      def gained = pipeline.commits_between(environment.version, version)
      # The last rehearsal of this version on production's data, nil when there was none.
      def rehearsal = pipeline.staging.rehearsal(version)

      private

      def dispatch = run_workflow(destination: destination, version: version)

      def request_attributes = { destination: destination, version: version }
    end
  end
end
