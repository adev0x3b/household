# frozen_string_literal: true

module AssistantEval
  module Checks
    class TherapyLinks < Base
      def self.key = "therapy_links"
      def self.argument = "Therapy (collection) name → how many supply purchases (purchases) and medication series (medications) belong to it"
      def self.example = { "MTX" => { "purchases" => 3, "medications" => 1 } }

      def call(expected)
        wrong = expected.filter_map do |name, want|
          therapy = Collection.where(profile: records.profile).find_by("LOWER(name) = ?", name.to_s.downcase)
          next "#{name}: no such therapy" if therapy.nil?

          have = { "purchases" => SupplyPurchase.where(collection: therapy).count,
                   "medications" => records.series("medication").where(collection_id: therapy.id).count }
          problems = want.filter_map { |key, count| "#{key} #{have[key]}" unless have[key] == count }
          "#{name}: #{problems.join(", ")}" if problems.any?
        end
        "therapy_links: #{wrong.join("; ")}" if wrong.any?
      end
    end
  end
end
