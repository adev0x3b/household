# frozen_string_literal: true

module Assistant
  # What each dose of a saved medication uses from now on. update_record
  # can change it too, but models looking for it reached for record_purchases
  # or a new medication instead, so it has a tool of its own.
  class SetDoseSuppliesTool < ChangeTool
    description "Saves which supplies each dose of an EXISTING medication uses from now on (\"I use a needle and a syringe " \
                "for each injection\", \"each dose takes 0.12 ml\"). Not a purchase — nothing was bought — and not a new " \
                "medication. List EVERY supply the user named for one dose."
    parameters(
      type: "object",
      properties: {
        medication: { type: "string", description: "The medication, in the user's words (\"cobalamin\"); leave out when they have only one" },
        event_id: EVENT_ID,
        uses: USES.merge(description: "Every supply one dose uses, the medication itself too, each with how many")
      },
      required: %w[uses]
    )

    def execute(medication: nil, event_id: nil, uses: [])
      uses = Array.wrap(uses)
      fail!("uses is empty — which supplies does each dose use?") if uses.empty?

      # A medication this chat is still creating takes them, since there is
      # nothing saved yet to update.
      if event_id.blank? && (pending = pending_medication(medication))
        return submit([ { op: "create", type: "medication", fields: { name: pending, uses: uses } } ])
      end

      ref = ref_or_event_id(medication, event_id) || only_series_ref
      submit([ { op: "update", type: "medication", ref: ref, fields: { uses: uses } } ])
    end

    private

    # The name of a medication this chat's change set is still creating:
    # the one named, or the only one.
    def pending_medication(named)
      set = ChangeSet.where(chat: chat).in_progress.order(:id).last
      return unless set

      names = set.operations.filter_map do |spec|
        spec = Operations.normalize(spec)
        (spec["fields"]["name"] || spec["fields"]["title"]).to_s.squish.presence if spec["op"] == "create" && spec["type"] == "medication"
      end
      return names.first if names.one? && named.blank?

      names.find { |name| named.present? && TextMatch.fold(name).include?(TextMatch.fold(named).split.first.to_s) }
    end

    # With no medication named, the only one that repeats is meant.
    def only_series_ref
      series = Medication.accessible_by(profile).where.not(rrule: nil).to_a
        .select { |event| event.occurrence_dates_between(Date.current, Date.current + Resources::CalendarResource::NEXT_DAY_WITHIN).any? }
      return "event_id #{series.sole.id}" if series.one?

      names = series.filter_map { |event| event.title.presence }.uniq
      fail!(names.any? ? "which medication? Give medication — one of: #{names.join(", ")}" : "there is no repeating medication to set supplies on — save it first with record_medication")
    end
  end
end
