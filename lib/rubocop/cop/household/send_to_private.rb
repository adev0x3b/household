# frozen_string_literal: true

module RuboCop
  module Cop
    module Household
      # Another object is called through its public methods:
      # `send` or `__send__` with a receiver reaches past its `private`, and
      # couples the caller to what the receiver meant to keep to itself. An
      # object may dispatch to its own methods (`send(:"check_#{kind}")`).
      #
      # @example
      #   # bad
      #   resolver.send(:dates_in, text)
      #   turbo_stream.send(action, "modals", view)
      #
      #   # good
      #   ChangeSets::Resolver.split_date(text)   # a public method on the owner
      #   turbo_stream.public_send(action, "modals", view)
      #   send(:"build_#{kind}")
      class SendToPrivate < Base
        MSG = "Call another object through its public methods (`public_send`, or give it one): `%<method>s` reaches past `private`."
        RESTRICT_ON_SEND = %i[send __send__].freeze

        def on_send(node)
          return if node.receiver.nil? || node.receiver.self_type?

          add_offense(node.loc.selector, message: format(MSG, method: node.method_name))
        end
        alias on_csend on_send
      end
    end
  end
end
