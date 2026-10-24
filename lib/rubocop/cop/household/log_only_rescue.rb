# frozen_string_literal: true

module RuboCop
  module Cop
    module Household
      # An error that is rescued and gone on from is reported: a
      # line in the log is read by nobody, and never reaches /admin/errors or
      # whoever runs the app. A rescue that writes to the logger is one that
      # thought the error worth noting, so it reports it, or raises again. A
      # rescue that turns an error into an answer (a refusal, a form's
      # error, nil for a date that doesn't parse) logs nothing and is let be.
      #
      # @example
      #   # bad
      #   rescue Error => e
      #     Rails.logger.warn("[books] #{e.message}")
      #     Answer.none(:unavailable)
      #
      #   # good
      #   rescue Error => e
      #     Rails.error.report(e, handled: true, severity: :warning, context: { isbn: isbn })
      #     Answer.none(:unavailable)
      class LogOnlyRescue < Base
        MSG = "Report what is rescued with `Rails.error.report`, or raise it again: a log line alone reaches nobody."
        LEVELS = %i[debug info warn error fatal unknown].freeze

        # @!method logs?(node)
        def_node_search :logs?, "(send (send {nil? (const {nil? cbase} :Rails)} :logger) {#{LEVELS.map(&:inspect).join(' ')}} ...)"

        # @!method reports?(node)
        def_node_search :reports?, "(send (send (const {nil? cbase} :Rails) :error) _ ...)"

        # @!method raises?(node)
        def_node_search :raises?, "(send nil? {:raise :fail} ...)"

        def on_resbody(node)
          return unless node.body && logs?(node.body)
          return if reports?(node.body) || raises?(node.body)

          add_offense(node.loc.keyword)
        end
      end
    end
  end
end
