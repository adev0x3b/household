# frozen_string_literal: true

module RuboCop
  module Cop
    module Household
      # Text is written as text: Phlex escapes it, and markup comes only from
      # a helper that builds it (`link_to`, `tag`), never from a string marked
      # safe. A toast once rendered a housemate's name as HTML that way (an
      # XSS through a display name).
      #
      # @example
      #   # bad
      #   raw(t("notices.shared", name: profile.display_name))
      #   "<b>#{name}</b>".html_safe
      #
      #   # good
      #   plain t("notices.shared", name: profile.display_name)
      #   helpers.link_to(t("…"), url)
      class HtmlSafe < Base
        MSG = "Write text as text; markup only from a helper that builds it (`link_to`, `tag`): `%<method>s` trusts a string that may hold what someone typed."
        RESTRICT_ON_SEND = %i[html_safe raw unsafe_raw].freeze

        def on_send(node)
          # raw / unsafe_raw are the view's own (no receiver); html_safe is asked of a string.
          return if !node.method?(:html_safe) && node.receiver

          add_offense(node.loc.selector, message: format(MSG, method: node.method_name))
        end
        alias on_csend on_send
      end
    end
  end
end
