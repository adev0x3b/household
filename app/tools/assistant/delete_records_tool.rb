# frozen_string_literal: true

module Assistant
  class DeleteRecordsTool < ChangeTool
    description "Deletes records: one by ref (an id from search_records or the user's words), or all: true for " \
                "\"delete all …\" (narrowed by query and dates). Nothing is deleted until the user presses the button."
    parameters(
      type: "object",
      properties: {
        type: { type: "string", enum: TYPES }, ref: { type: "string" }, event_id: EVENT_ID, all: { type: "boolean" },
        query: { type: "string", description: "With all: only records matching these words" },
        date_from: DATE, date_to: DATE,
        whole_series: { type: "boolean", description: "The whole repeating series, not just one day of it" }
      },
      required: %w[type]
    )

    def execute(type: nil, ref: nil, event_id: nil, all: false, query: nil, date_from: nil, date_to: nil, whole_series: false)
      ref = ref_or_event_id(ref, event_id)
      type ||= type_from_event_id(event_id)
      fail!("give type, or event_id") if type.blank?
      fail!("give ref, or all: true") if ref.blank? && !all

      submit([ { op: "delete", type: type, ref: ref.presence,
                 fields: { all: all || nil, query: query, date_from: date_from, date_to: date_to,
                           scope: ("series" if whole_series) } } ])
    end
  end
end
