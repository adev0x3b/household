# frozen_string_literal: true

module AssistantEval
  module Checks
    class Saves < Turns
      def self.key = "saves"
      def self.argument = "Turn number that must save something"
      def self.example = 2

      def call(number)
        turn = turn_at(number)
        return if turn.nil?

        "saves: turn #{number} saved nothing" unless turn.applied.to_i.positive?
      end
    end
  end
end
