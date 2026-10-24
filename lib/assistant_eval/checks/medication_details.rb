# frozen_string_literal: true

module AssistantEval
  module Checks
    # A series split "from now on" leaves the old one behind, so the latest
    # series of that name is the one judged.
    class MedicationDetails < Base
      def self.key = "medication_details"
      def self.argument = "A medication (name words): any of kind / area / side / quantity / unit / uses (supply → quantity per dose)"
      def self.example = { "name" => "methotrexate", "kind" => "injection", "area" => "thigh", "side" => "left" }

      def call(want)
        medication = records.series("medication").order(starts_on: :desc, id: :desc).to_a.find { |m| named?(m, want["name"]) }
        return "medication_details: no medication #{want["name"]}" unless medication

        details = medication.details
        problems = %w[kind area side unit].filter_map { |field| "#{field} #{details[field]}" if want[field] && details[field].to_s != want[field].to_s }
        problems << "quantity #{details.quantity.to_f}" if want["quantity"] && !same_number?(details.quantity, want["quantity"])
        Array(want["uses"]).each do |supply, quantity|
          used = details.supply_uses.find { |use| use.supply.name.downcase.include?(supply.to_s.downcase) }
          problems << "uses #{supply} #{used&.quantity.to_f}" unless used && same_number?(used.quantity, quantity)
        end
        "medication_details: #{problems.join(", ")}" if problems.any?
      end
    end
  end
end
