# frozen_string_literal: true

module Delivery
  module Presses
    # Dev stopped, its data kept, until a preview starts it again; nothing
    # to press while it isn't running.
    class Stop < Base
      def self.kind = :stop
      def icon = "fa-power-off"
      def destination = "dev"
      def blocked? = !pipeline.dev.running?

      private

      def dispatch = run_workflow(destination: destination)

      def request_attributes = { destination: destination }

      def check
        super
        errors.add(:base, :not_running, destination: I18n.t("admin.deployment.destinations.dev")) if blocked?
      end
    end
  end
end
