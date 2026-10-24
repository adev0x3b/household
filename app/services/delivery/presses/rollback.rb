# frozen_string_literal: true

module Delivery
  module Presses
    # Production back to an earlier version it ran: the one picked, else the
    # newest. The password, the version typed back, and a reason.
    class Rollback < Base
      # Versions offered to roll back to.
      VERSIONS = 6

      def self.kind = :rollback
      def icon = "fa-rotate-left"
      def destination = "production"
      def danger? = true
      def reason_required? = true
      def gated? = true
      def version = super.presence || candidates.first&.sha

      # Earlier versions production ran, newest first, other than the one it runs.
      def candidates
        @candidates ||= Github.records(environment: "production", limit: 15).select(&:succeeded?)
          .reject { _1.sha == pipeline.production.version }.uniq(&:sha).first(VERSIONS)
      end

      private

      def dispatch = run_workflow(destination: destination, version: version)

      def request_attributes = { destination: destination, version: version }

      def check
        super
        errors.add(:base, :version_required) if version.blank?
      end
    end
  end
end
