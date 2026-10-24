# frozen_string_literal: true

module AssistantEval
  module Checks
    class Statuses < Base
      def self.key = "statuses"
      def self.argument = "How many saved records of a type in a date range have this status"
      def self.example = { "type" => "medication", "from" => "2026-09-21", "to" => "2026-09-27", "status" => "completed", "count" => 1 }

      def call(want)
        range = Date.parse(want["from"].to_s)..Date.parse(want["to"].to_s)
        have = records.days(want["type"]).where(date: range, status: want["status"].to_s).count
        "statuses: #{want["type"]} #{want["status"]} #{range}: expected #{want["count"]}, got #{have}" unless have == want["count"].to_i
      end
    end
  end
end
