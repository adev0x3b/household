# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # A calendar kind's draft: a new series and its first day, which is
    # #record. The day is saved with the series, so what was just created
    # has an id the chat, the card and an Undo can name.
    class Series < DraftBuilder
      # What every series has; the rest of a kind's writable fields are its
      # details', or the first day's (DAY_FIELDS).
      SERIES_FIELDS = %w[title notes location start_time duration_minutes].freeze
      DAY_FIELDS = %w[time anchor skipped_reason completed_at].freeze

      def series = record.event

      # The recurrence fields for Occurrences::Create (the slots are already
      # on the built series).
      def recurrence_fields = recurrence&.slice("frequency", "interval", "week_days", "ends")&.symbolize_keys

      # Same-looking items around its day, and the series it may belong to.
      def duplicates
        query = duplicate_query
        return [] if query.blank?

        date = record.date
        return series_around(query, Date.current) unless date

        found = resource.search(profile, query: query, date_from: date - duplicate_window, date_to: date + duplicate_window)
        found + series_around(query, date).reject { |series| found.any? { |summary| summary[:event_id] == series[:event_id] } }
      end

      # A model may create a second series for "I took it", "skip it" or
      # "every Monday and Thursday from now on", so the hint names the
      # tools that change the series there is.
      def duplicate_hint(existing)
        return if existing["repeats"].blank? || existing["event_id"].blank?

        "This already repeats (event_id #{existing["event_id"]}). If the user means it — taken, skipped, new days, dose or " \
          "the supplies it uses — don't create another: use mark_done or update_record with ref \"event_id #{existing["event_id"]}\" instead."
      end

      # The very same thing on the very same day is not "maybe a duplicate":
      # the model is sending something already saved again, so the call is
      # refused naming the tools that act on it.
      def screen(warnings, _acknowledged)
        twin = same_day_twin(warnings)
        return super unless twin

        existing = twin["existing"]
        Screening.new(warnings: warnings - [ twin ],
                      refusal: "this #{kind} already exists on #{record.date} (id #{existing["id"]}). To mark it done use mark_done with ref " \
                               "#{existing["id"]}; to change it use update_record with ref #{existing["id"]}. Only create it again if " \
                               "the user really has two.")
      end

      def save!(committer)
        day = record
        Occurrences::Create.call(series, by: profile, recurrence: recurrence_fields, collection_id: collection_id)
        day.save!
        committer.keep(day)
        committer.broadcast(series)
        attach_fee(committer, day) if cost_requested?
        day.complete!(at: day.completed_at || Time.current) if done?(day)
      end

      # "Visit Moretti 11:00 on 2 October 2026": a new series by its first day.
      def label = with_date(series.title.presence || type_label, record.date)

      private

      def recurrence = draft.section("recurrence").presence

      def build
        attributes = writable_attributes
        date = attributes.delete("date")
        day = attributes.extract!(*DAY_FIELDS)
        details = attributes.except(*SERIES_FIELDS)
        details["amount"] = Normalize.amount(details["amount"]) if details.key?("amount")

        event = resource.type.new(attributes.slice(*SERIES_FIELDS).merge(
                                    profile: profile, starts_on: date, collection_id: Occurrences::Create.accessible_collection_id(profile, collection_id)
                                  ))
        event.details.assign_attributes(details)
        slots = slot_entries(day)
        event.assign_slots(slots) if slots.any?
        fill_in(event, details)

        first = event.starts_on ? event.first_occurrence : Occurrence.new(event: event, time: event.first_slot.first, anchor: event.first_slot.last)
        first.assign_attributes(day.slice("skipped_reason", "completed_at"))
        first
      end

      # What people leave unsaid that the kind can tell from what they did
      # say (`given`: the details they said).
      def fill_in(_event, _given) = nil

      # The times of the day: the recurrence's, else the one time said.
      def slot_entries(day)
        listed = Array(recurrence&.dig("slots").presence || recurrence&.dig("times_of_day")).compact_blank
        listed = [ day["anchor"].presence || day["time"].presence ].compact if listed.empty?
        listed.filter_map { |entry| Events::TimesOfDay.code_for(entry) }
      end

      # The words a duplicate is searched by, and how many days around its
      # date one counts.
      def duplicate_query = record.title
      def duplicate_window = 0

      # A series it may belong to, around `date`: a medication's only.
      def series_around(_query, _date) = []

      def same_day_twin(warnings)
        date = record.date
        date && warnings.find { |warning| warning.dig("existing", "date") == date.iso8601 && warning.dig("existing", "id") }
      end

      # The fee paid for the day, saved with it: a visit's, a meal out's.
      def attach_fee(_committer, _day) = nil

      # Something dated in the past already happened: a lab result from last
      # week, a visit yesterday. Future and today's items stay pending unless
      # the model says the user already did it.
      def done?(day)
        case requested_status
        when "completed" then true
        when "pending" then false
        else day.date < Date.current
        end
      end
    end
  end
end
