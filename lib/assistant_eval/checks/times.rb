# frozen_string_literal: true

module AssistantEval
  module Checks
    class Times < Base
      def self.key = "times"
      def self.argument = "The doses of a day of a medication series: times (HH:MM) or anchors (CM breakfast, CD lunch, CV dinner, HS bedtime)"
      def self.example = { "name" => "metformin", "times" => %w[CM CV] }

      def call(want)
        event = records.series("medication").order(starts_on: :desc, id: :desc).to_a.find { |e| named?(e, want["name"]) }
        return "times: no medication series #{want["name"]}" unless event

        expected = Events::TimesOfDay.expand(Array(want["times"]).map { |t| Events::TimesOfDay.code_for(t) })
        have = event.timed? ? event.slots : []
        "times: #{have.inspect}, expected #{expected.inspect}" unless have == expected
      end
    end
  end
end
