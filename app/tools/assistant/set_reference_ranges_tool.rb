# frozen_string_literal: true

module Assistant
  class SetReferenceRangesTool < ChangeTool
    description "Saves reference (normal) ranges, one item per analyte, all in one call. Give the bounds as numbers, " \
                "or copy the user's own sentence for that analyte into range_text."
    parameters(
      type: "object",
      properties: {
        ranges: {
          type: "array",
          items: {
            type: "object",
            properties: {
              analyte: { type: "string" }, unit: { type: "string", description: "Only if the user said it" },
              low: { type: "number" }, high: { type: "number" },
              critical_low: { type: "number" }, critical_high: { type: "number" },
              range_text: { type: "string", description: "The user's words about this analyte's range" },
              sex: { type: "string", enum: ReferenceRange.sexes.keys, description: "Only when the range is for one sex" }
            },
            required: %w[analyte]
          }
        }
      },
      required: %w[ranges]
    )

    def execute(ranges: [])
      fail!("ranges is empty") if Array(ranges).empty?

      submit(items_of(ranges).map { |range| { op: "set_range", type: "reference_range", fields: range.is_a?(Hash) ? range : { "range_text" => range } } })
    end
  end
end
