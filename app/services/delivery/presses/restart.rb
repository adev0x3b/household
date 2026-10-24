# frozen_string_literal: true

module Delivery
  module Presses
    # Any destination, with the version it runs: the one given, else this copy.
    class Restart < Base
      def self.kind = :restart
      def icon = "fa-arrow-rotate-right"
      def destination = (super.presence || Deployment.destination).presence_in(Deployment::DESTINATIONS)
      def gated? = destination == "production"

      private

      def dispatch = run_workflow(destination: destination)

      def request_attributes = { destination: destination }

      def check
        super
        errors.add(:base, :destination_required) if destination.blank?
      end
    end
  end
end
