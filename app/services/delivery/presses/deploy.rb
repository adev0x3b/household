# frozen_string_literal: true

module Delivery
  module Presses
    # Only the mainline takes main's versions. A production deploy of a version
    # that needs the app stopped is blocked, since Release is the way to ship it.
    class Deploy < Base
      def self.kind = :deploy
      def icon = "fa-rocket"
      def destination = (super.presence || Deployment.destination).presence_in(Deployment::MAINLINE)
      def version = super.presence || pipeline.head.sha
      def gated? = destination == "production"
      def blocked? = gated? && held.any?

      # The migrations the version adds over what runs there that need the app stopped.
      def held
        @held ||= environment ? pipeline.held_between(environment.version, version) : []
      end

      # The commits the destination would gain.
      def gained = environment ? pipeline.commits_between(environment.version, version) : []

      private

      def dispatch = run_workflow(destination: destination, version: version)

      def request_attributes = { destination: destination, version: version }

      def check
        super
        errors.add(:base, :destination_required) if destination.blank?
        errors.add(:base, :held, count: held.size) if blocked?
      end
    end
  end
end
