# frozen_string_literal: true

class Assistant::Draft
  # A lab report's values arrive as {"Cobalamin": "250"}, [{"analyte": …,
  # "value": …}] or ["Cobalamin: 250 pg/mL"], at the top level or inside
  # the report's section. All become the top-level "entries":
  #   [{ "analyte_name" => "Cobalamin", "value" => "250", "unit_name" => "pg/mL" }]
  class LabTestResultShape < Shape
    private

    def read_values!(normalized)
      section = normalized[kind].is_a?(Hash) ? normalized[kind] : {}
      raw = LAB_VALUE_KEYS.flat_map do |key|
        [ normalized.key?(key) ? normalized.delete(key) : nil, section.key?(key) ? section.delete(key) : nil ]
      end.compact
      return if raw.empty?

      entries = raw.flat_map { |value| Assistant::Draft.lab_entries(value) }
      normalized["entries"] = entries.reverse.uniq { |entry| entry["analyte_name"].downcase }.reverse
    end
  end
end
