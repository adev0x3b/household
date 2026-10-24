# frozen_string_literal: true

module AssistantEval
  module Checks
    # A series split "from now on" leaves the old one behind, so the latest
    # series of that name is the one judged.
    class Repeats < Base
      def self.key = "repeats"
      def self.argument = "How a series repeats: frequency (none = it doesn't), interval, weekdays, ends (last possible date)"
      def self.example = { "type" => "medication", "name" => "cobalamin", "frequency" => "weekly", "weekdays" => %w[monday thursday] }

      def call(want)
        event = records.series(want["type"]).order(starts_on: :desc, id: :desc).to_a.find { |e| named?(e, want["name"]) }
        return "repeats: no #{want["type"]} series #{want["name"]}" unless event

        problems = problems_of(Events::RecurrenceRule.describe(event.rrule), want)
        "repeats: #{problems.join(", ")}" if problems.any?
      end

      private

      def problems_of(have, want)
        problems = []
        problems << "frequency #{have[:frequency]}" if want["frequency"] && have[:frequency].to_s != want["frequency"].to_s
        problems << "interval #{have[:interval]}" if want["interval"] && have[:interval].to_i != want["interval"].to_i
        problems << "weekdays #{Array(have[:week_days]).sort}" if want["weekdays"] && Array(have[:week_days]).sort != Array(want["weekdays"]).map(&:to_s).sort
        problems << "ends #{have[:ends].inspect}" if want["ends"] && have[:ends] != Date.parse(want["ends"].to_s)
        problems
      end
    end
  end
end
