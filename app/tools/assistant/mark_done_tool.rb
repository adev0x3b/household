# frozen_string_literal: true

module Assistant
  # Cancelling keeps the item, marked cancelled, because the user may want
  # to see it later; removing it is delete_records.
  class MarkDoneTool < ChangeTool
    STATUSES = %w[done not_done skipped cancelled in_progress].freeze

    description "Sets the status of existing items: done (taken, paid) or another status, and for a medication dose " \
                "already taken, the supplies it used (uses). \"Cancel\" or \"skip\" keeps the item with that status — " \
                "never delete it for that. A meal marked done takes its recipes' ingredients out of the pantry. ref: an id from search_records or the user's words (\"the visit today\"); " \
                "for several at once (\"all my doses this week\", \"every injection this month\") use all: true with " \
                "date_from/date_to instead of ref — one call marks them all, don't call this once per item."
    parameters(
      type: "object",
      properties: {
        type: { type: "string", enum: %w[appointment medication task transaction lab_test_result meal] },
        ref: { type: "string" }, event_id: EVENT_ID,
        date: DATE.merge(description: "The item's day (\"yesterday\"), with ref — or with all, just that day"),
        time: { type: "string", description: "Medication only: which dose of the day (HH:MM, or breakfast / lunch / dinner / bedtime) when it has several" },
        status: { type: "string", enum: STATUSES, description: "Default done" },
        reason: { type: "string", enum: Medication.skip_reasons, description: "Medication only, with skipped: why the dose wasn't taken — only if the user said" },
        all: { type: "boolean", description: "Every matching item still not done in the dates (\"all my doses this week\")" },
        query: { type: "string", description: "With all: only items matching these words" },
        date_from: DATE, date_to: DATE,
        uses: USES.merge(description: "Medication only: supplies this dose used — only if the user said so"),
        undo: { type: "boolean", description: "Same as status not_done" }
      },
      required: %w[type]
    )

    def execute(type: nil, ref: nil, event_id: nil, date: nil, time: nil, status: nil, reason: nil, all: false, query: nil, date_from: nil,
                date_to: nil, uses: nil, undo: false)
      ref = ref_or_event_id(ref, event_id)
      type ||= type_from_event_id(event_id)
      fail!("give type, or event_id") if type.blank?
      if date.present? && all
        date_from ||= date
        date_to ||= date
      elsif date.present?
        ref = [ ref, date ].compact_blank.join(" ") # the resolver reads the day out of ref ("42 2026-09-24", "cobalamin yesterday")
      end
      ref = "#{ref} at #{time}" if ref.present? && time.present? # which dose of the day (the resolver reads it)
      fail!("give ref (an id from search_records, or the user's words), or all: true with dates") if ref.blank? && !all

      status = "not_done" if undo
      op, fields =
        case status.presence || "done"
        when "done" then [ "complete", {} ]
        when "not_done" then [ "uncomplete", {} ]
        else [ "set_status", { status: status, skipped_reason: (reason if status == "skipped") } ]
        end
      fields = fields.merge(all: all || nil, query: query, date_from: date_from, date_to: date_to, uses: uses)
      submit([ { op: op, type: type, ref: ref.presence, fields: fields } ])
    end
  end
end
