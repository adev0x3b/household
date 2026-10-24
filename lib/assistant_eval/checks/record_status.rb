# frozen_string_literal: true

module AssistantEval
  module Checks
    # A day nothing was saved about doesn't count: the record must be saved.
    class RecordStatus < Base
      def self.key = "record_status"
      def self.argument = "The saved record of a type on a day (optionally by name words; time picks one dose of several) has this status"
      def self.example = { "type" => "medication", "date" => "2026-09-24", "name" => "cobalamin", "status" => "skipped" }

      def call(want)
        date = Date.parse(want["date"].to_s)
        time = want["time"] && Events::TimesOfDay.hhmm(Events::TimesOfDay.code_for(want["time"]))
        record = records.days(want["type"]).where(date: date).order(:id).to_a
          .find { |r| named?(r, want["name"]) && (time.nil? || r.time_string == time) }
        return "record_status: no saved #{want["type"]} on #{date}#{" at #{time}" if time}" unless record

        "record_status: #{want["type"]} on #{date} is #{record.status}, expected #{want["status"]}" unless record.status == want["status"].to_s
      end
    end
  end
end
