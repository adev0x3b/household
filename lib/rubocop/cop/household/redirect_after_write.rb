# frozen_string_literal: true

module RuboCop
  module Cop
    module Household
      # A redirect after a write is a 303: a 302 lets the browser
      # (and Turbo's fetch) replay the PATCH or DELETE that was just done.
      # Checked in create, update and destroy, the actions that always write;
      # a custom write action follows the same rule unchecked.
      #
      # @example
      #   # bad
      #   def update
      #     redirect_to links_path
      #   end
      #
      #   # good
      #   def update
      #     redirect_to links_path, status: :see_other
      #   end
      class RedirectAfterWrite < Base
        MSG = "Redirect after a write with `status: :see_other`: a 302 can replay the request."
        RESTRICT_ON_SEND = %i[redirect_to redirect_back redirect_back_or_to].freeze
        WRITES = %i[create update destroy].freeze

        def on_send(node)
          action = node.each_ancestor(:def).first
          return unless action && WRITES.include?(action.method_name)
          return if status_given?(node)

          add_offense(node.loc.selector)
        end

        private

        def status_given?(node)
          node.arguments.any? { |argument| argument.hash_type? && argument.keys.any? { |key| key.sym_type? && key.value == :status } }
        end
      end
    end
  end
end
