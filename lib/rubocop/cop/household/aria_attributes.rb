# frozen_string_literal: true

module RuboCop
  module Cop
    module Household
      # An ARIA attribute is written the way a browser reads it.
      #
      # It goes in an `aria:` hash, as `data:` does. Phlex turns
      # `aria_label:` into aria-label, but a Rails builder (`f.submit`,
      # `button_to`) writes the key as it is, so the one way that works for
      # both is the only way. A builder that takes no nested hash, such as
      # will_paginate's, is given the attribute's own name ("aria-label").
      #
      # Its state is the word "true" or "false". Phlex writes a `true`
      # attribute bare and leaves a `false` one out, and ARIA reads a bare
      # aria-hidden as undefined, so the icon it was meant to hide is read
      # into its button's name.
      #
      # @example
      #   # bad
      #   button(aria_label: "Close", aria_expanded: "false")
      #   span(aria: { hidden: true })
      #   span("aria-hidden": true)
      #
      #   # good
      #   button(aria: { label: "Close", expanded: "false" })
      #   span(aria: { hidden: "true" })
      class AriaAttributes < Base
        extend AutoCorrector

        HASH = "Write `%<key>s:` in an `aria:` hash, as `data:` is written."
        BOOLEAN = "An ARIA state is the string %<word>s: Phlex writes `%<value>s` %<how>s, which ARIA reads as undefined."

        def on_pair(node)
          if flat_aria_key?(node.key)
            add_offense(node.key, message: format(HASH, key: node.key.value))
          elsif boolean?(node.value) && (inside_aria_hash?(node) || named_attribute?(node.key))
            flag_boolean(node.value)
          end
        end

        private

        def flat_aria_key?(key) = key.sym_type? && key.value.to_s.start_with?("aria_")

        def named_attribute?(key) = (key.sym_type? || key.str_type?) && key.value.to_s.start_with?("aria-")

        def boolean?(value) = value.true_type? || value.false_type?

        def inside_aria_hash?(pair)
          outer = pair.parent&.parent
          outer&.pair_type? && (outer.key.sym_type? || outer.key.str_type?) && outer.key.value.to_s == "aria"
        end

        def flag_boolean(value)
          word = value.true_type? ? "true" : "false"
          how = value.true_type? ? "as a bare attribute" : "not at all"

          add_offense(value, message: format(BOOLEAN, word: %("#{word}"), value: word, how: how)) do |corrector|
            corrector.replace(value, %("#{word}"))
          end
        end
      end
    end
  end
end
