# frozen_string_literal: true

module AssistantEval
  module Checks
    # What is shared is a record's whole series, so a day stands for its series.
    class SharedWith < Base
      THERAPY = %w[medical_therapy collection therapy].freeze

      def self.key = "shared_with"
      def self.argument = "Who a record (type, name, date) or a therapy (type collection) is shared with, by first name"
      def self.example = { "type" => "appointment", "name" => "Moretti", "date" => "2026-10-02", "with" => [ "Marco" ] }

      def call(want)
        therapy = THERAPY.include?(want["type"].to_s)
        found = therapy ? find_therapy(want) : find_record(want)
        return "shared_with: no #{therapy ? "therapy" : want["type"]} #{want["name"]}" if found.nil?

        shared = (therapy ? found.collection_shares : found.event.event_shares).map { |s| s.profile.first_name }
        expected = Array(want["with"])
        "shared_with: #{shared.sort}, expected #{expected.sort}" unless shared.map(&:downcase).sort == expected.map { |n| n.to_s.downcase }.sort
      end

      private

      def find_therapy(want) = Collection.where(profile: records.profile).to_a.find { |t| named?(t, want["name"]) }

      def find_record(want)
        scope = records.days(want["type"])
        scope = scope.where(date: Date.parse(want["date"].to_s)) if want["date"]
        scope.to_a.find { |r| named?(r, want["name"]) }
      end
    end
  end
end
