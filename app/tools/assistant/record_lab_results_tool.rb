# frozen_string_literal: true

module Assistant
  class RecordLabResultsTool < ChangeTool
    description "Saves a lab report with ALL its values in one call (one report, many values). Reference (normal) " \
                "ranges the doctor gave go to set_reference_ranges, not here. To fix a saved report use update_record."
    parameters(
      type: "object",
      properties: {
        values: {
          type: "array", description: "Every value in the report",
          items: { type: "object", properties: { analyte: { type: "string", description: "What was measured" },
                                                 value: { type: "string" }, unit: { type: "string", description: "Only if the user said it" } },
                   required: %w[analyte value] }
        },
        date: DATE.merge(description: "When the test was done. #{DATE[:description]}"),
        title: { type: "string" }, notes: { type: "string" }, **RECURRENCE, therapy: THERAPY, confirm: CONFIRM
      },
      required: %w[values]
    )

    def execute(values: [], date: nil, title: nil, notes: nil, repeat: nil, every: nil, days: nil, ends: nil, therapy: nil, confirm: false)
      submit([ { op: "create", type: "lab_test_result",
                 fields: { values: values, date: date, title: title, notes: notes, therapy: therapy,
                           recurrence: recurrence(repeat, every, days, ends) } } ], confirm: confirm)
    end
  end
end
