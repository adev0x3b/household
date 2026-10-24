# frozen_string_literal: true

module AssistantEval
  module Checks
    # A check on the turns of a scenario: what a turn saved or asked and what
    # the replies said. A turn whose message is a button press ("!confirm")
    # got no reply from the model, so only the others are judged.
    class Turns < Base
      BUTTON = /\A!(?!photo)/

      def self.about_turns? = true

      private

      def turn_at(number) = turns[number.to_i - 1]

      # Turns the model answered, with their number in the chat.
      def model_turns = turns.each_with_index.reject { |turn, _| turn.said.to_s.match?(BUTTON) }.map { |turn, i| [ turn, i + 1 ] }

      # What a reply says to the user, without the model's thinking.
      def said(turn) = Assistant::ModelReply.new(turn.reply).answer
    end
  end
end
