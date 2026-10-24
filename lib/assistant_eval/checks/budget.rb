# frozen_string_literal: true

module AssistantEval
  module Checks
    class Budget < Turns
      def self.key = "budget"
      def self.argument = "Limits over the whole scenario: tool_calls (all turns), seconds, and/or tokens_per_step (the largest prompt any step sent)"
      def self.example = { "tool_calls" => 3, "seconds" => 90, "tokens_per_step" => 11_000 }

      def call(limits)
        calls = turns.sum { |turn| Array(turn.tools).size }
        seconds = turns.sum { |turn| turn.seconds.to_f }
        largest = turns.map { |turn| turn.max_step_input.to_i }.max.to_i
        problems = []
        problems << "#{calls} tool calls > #{limits["tool_calls"]}" if limits["tool_calls"] && calls > limits["tool_calls"].to_i
        problems << "#{seconds.round}s > #{limits["seconds"]}s" if limits["seconds"] && seconds > limits["seconds"].to_f
        problems << "a step sent #{largest} tokens > #{limits["tokens_per_step"]}" if limits["tokens_per_step"] && largest > limits["tokens_per_step"].to_i
        "budget: #{problems.join(", ")}" if problems.any?
      end
    end
  end
end
