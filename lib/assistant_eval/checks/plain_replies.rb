# frozen_string_literal: true

module AssistantEval
  module Checks
    # The prompt tells the model to use everyday words, so ids, tool and field
    # names and code never reach the user. snake_case covers every tool and
    # field name.
    class PlainReplies < Turns
      JARGON = Regexp.union(/`[^`]+`/, /\b[a-z]+_[a-z_]+\b/, /\b(?:id|ID|Id)\s*[:#=]?\s*\d+\b/, /\bref\s*[:=]/i, /\{"/)

      def self.key = "plain_replies"
      def self.argument = "On for every scenario: replies never show ids, tool or field names, or code. false to switch it off"
      def self.example = false
      def self.on_by_default? = true

      def call(on)
        return unless on

        jargon = model_turns.filter_map do |turn, number|
          found = said(turn)[JARGON]
          "turn #{number} shows \"#{found}\"" if found
        end
        "plain_replies: #{jargon.join("; ")}" if jargon.any?
      end
    end
  end
end
