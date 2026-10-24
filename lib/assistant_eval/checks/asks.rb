# frozen_string_literal: true

module AssistantEval
  module Checks
    class Asks < Turns
      def self.key = "asks"
      def self.argument = "Turn number that must end asking the user (needs input or their OK), saving nothing"
      def self.example = 1

      def call(number)
        turn = turn_at(number)
        return if turn.nil?

        problems = []
        problems << "saved something" if turn.applied.to_i.positive?
        problems << "didn't end asking the user" unless turn.asked
        "asks: turn #{number} #{problems.join(" and ")}" if problems.any?
      end
    end
  end
end
