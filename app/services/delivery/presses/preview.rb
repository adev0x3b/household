# frozen_string_literal: true

module Delivery
  module Presses
    # A branch on dev, its image built first; on fresh data when asked.
    class Preview < Base
      def self.kind = :preview
      def icon = "fa-code-branch"
      def destination = "dev"
      def ref = super.to_s.strip.presence

      # Fresh data by default when nothing runs there (or its branch is
      # unknown), else kept; what the admin ticked wins.
      def fresh
        chosen = super
        chosen.nil? ? pipeline.dev.branch.blank? : chosen
      end

      private

      def dispatch = run_workflow(destination: destination, branch: ref, fresh: fresh)

      def request_attributes = { destination: destination, ref: ref, fresh: fresh }

      def check
        super
        errors.add(:base, :branch_required) if ref.blank?
      end
    end
  end
end
