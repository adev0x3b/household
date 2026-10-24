# frozen_string_literal: true

module Delivery
  module Presses
    # The automatic path to staging let go again. The password.
    class Unfreeze < Base
      def self.kind = :unfreeze
      # GitHub has nothing to run: the variable is set or it isn't.
      def self.instant? = true
      def icon = "fa-snowflake"
      def destination = nil
      def gated? = true

      private

      def dispatch
        Github.delete_variable(Github::FREEZE)
        Github.delete_variable(Github::FREEZE_NOTE)
      end
    end
  end
end
