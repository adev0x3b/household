# frozen_string_literal: true

module Assistant
  class RecordMedicationTool < ChangeTool
    description "Saves a NEW medication — the first dose of it, once or on a schedule — and the default supplies each " \
                "future dose uses. For a dose of a medication already saved (a scheduled one taken, skipped, or its " \
                "supplies), or to change how an existing one repeats, use mark_done or update_record instead."
    parameters(
      type: "object",
      properties: {
        name: { type: "string" }, kind: { type: "string", enum: Medication::Details.kinds.keys },
        quantity: { type: "number", description: "The dose" }, unit: { type: "string" },
        area: { type: "string", enum: Medication::Details.areas.keys }, side: { type: "string", enum: Medication::Details.sides.keys },
        date: DATE, taken: { type: "boolean", description: "Already taken" }, uses: USES,
        **RECURRENCE, times: TIMES,
        therapy: THERAPY, confirm: CONFIRM
      },
      required: %w[name]
    )

    def execute(name: nil, kind: nil, quantity: nil, unit: nil, area: nil, side: nil, date: nil, taken: nil, uses: nil,
                repeat: nil, every: nil, days: nil, ends: nil, times: nil, therapy: nil, confirm: false)
      status = { true => "completed", false => "pending" }[taken]
      submit([ { op: "create", type: "medication",
                 fields: { name: name, kind: kind, quantity: quantity, unit: unit, area: area, side: side, date: date,
                           status: status, therapy: therapy, uses: uses, recurrence: recurrence(repeat, every, days, ends, times) } } ], confirm: confirm)
    end
  end
end
