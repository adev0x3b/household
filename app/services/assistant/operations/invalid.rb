# frozen_string_literal: true

module Assistant
  module Operations
    # An op the model named wrongly: reported back, never applied.
    class Invalid < Base
      def initialize(spec, index:, context:, reason:)
        super(spec, index:, context:)
        @reason = reason
      end

      def phase = raise(ArgumentError, @reason)
      def check = fail!(@reason)
      def apply!(_applier) = raise(ArgumentError, @reason)
    end
  end
end
