# frozen_string_literal: true

module Delivery
  module Presses
    # The automatic path to staging held: a push to main builds its image
    # and stops there. The password, and a reason the console shows.
    class Freeze < Base
      def self.kind = :freeze
      # GitHub has nothing to run: the variable is set or it isn't.
      def self.instant? = true
      def icon = "fa-snowflake"
      def destination = nil
      def reason_required? = true
      def gated? = true

      private

      def dispatch
        Github.set_variable(Github::FREEZE, "true")
        Github.set_variable(Github::FREEZE_NOTE, "#{@request.profile.username} · #{I18n.l(Date.current)} · #{@request.reason}")
      end
    end
  end
end
