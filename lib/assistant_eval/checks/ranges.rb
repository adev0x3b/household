# frozen_string_literal: true

module AssistantEval
  module Checks
    # Only the bounds a scenario gives are checked; `sex` picks which of an
    # analyte's ranges, any by default.
    class Ranges < Base
      def self.key = "ranges"
      def self.argument = "Analyte → reference range bounds (only those given are checked; sex picks the range)"
      def self.example = { "Cobalamin" => { "low" => 150, "high" => 250 } }

      def call(expected)
        ranges = ReferenceRange.where(analyte: records.profile.analytes).includes(:analyte)
        wrong = expected.filter_map do |analyte, bounds|
          sex = bounds["sex"]
          range = ranges.find { |r| r.analyte.name.casecmp?(analyte.to_s) && (sex.nil? || r.sex == sex.to_s) }
          next "#{analyte}: missing" if range.nil?

          off = bounds.except("sex").reject { |key, value| same_number?(range[key], value) }
          "#{analyte}: #{off.keys.map { |k| "#{k} #{range[k]&.to_f.inspect}≠#{bounds[k]}" }.join(", ")}" if off.any?
        end
        "ranges: #{wrong.join("; ")}" if wrong.any?
      end
    end
  end
end
