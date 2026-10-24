# frozen_string_literal: true

module Assistant
  module Operations
    class Update < Base
      # How a series repeats, and a medication's doses of the day. The model
      # sends only what changes, so it is merged into the series' rule.
      class Recurrence < Part
        def initialize(record, given, profile:)
          super(record, profile: profile)
          @given = given.to_h.stringify_keys.compact
        end

        def series_level? = true

        def check
          fail!("only calendar items repeat") unless day?
          @given["slots"] ||= @given.delete("times_of_day") if @given.key?("times_of_day")
          fail!("times are only for a medication") if @given["slots"] && !record.event.is_a?(Medication)
          event = record.event
          frequency = @given["frequency"]
          fail!("repeat must be one of: #{Events::RecurrenceRule::FREQUENCIES.join(", ")}") if frequency && !Events::RecurrenceRule::FREQUENCIES.include?(frequency)
          fail!("it doesn't repeat, so it can't end — give repeat to make it repeat") if frequency.nil? && !event.recurring? && @given.key?("ends")
          return unless @given["ends"] && Date.iso8601(@given["ends"]) < event.starts_on

          fail!("it started on #{event.starts_on.iso8601}, so it can't end before that")
        end

        def before = { event_before: series_snapshot(record.event) }

        # With a change to the day as well: the series takes the new rule,
        # or goes on from today as a new one (Events::Reschedule), which
        # the undo log then also knows as created.
        def apply!(applier)
          continuation = reschedule!(applier)
          continuation ? [ entry("created", continuation) ] : []
        end

        # A change to the series only (no field of this day).
        def apply_alone!(applier)
          event = record.event
          event_before = series_snapshot(event)
          applier.defer([ -> { Calendar::DayCardBroadcaster.call(event: event) } ])
          continuation = reschedule!(applier)
          entries = [ entry("series", event, event_before: event_before) ]
          return entries.tap { applier.saved([ summarize(record) ]) } unless continuation

          applier.saved([ summarize(continuation.first_occurrence) ])
          entries << entry("created", continuation)
        end

        private

        def series_snapshot(event)
          { "starts_on" => event.starts_on.iso8601, "rrule" => event.rrule,
            "slots" => event.event_slots.map { |slot| slot.anchor || slot.time_string } }
        end

        # The series' rule with these changes; a new frequency drops weekdays that no longer apply.
        def merged_rule(event)
          current = Events::RecurrenceRule.describe(event.rrule).stringify_keys
          current = {} if current["frequency"] == "none"
          changes = @given.except("slots")
          merged = current.merge(changes)
          merged.delete("week_days") if changes["frequency"] && changes["frequency"] != current["frequency"] && !changes.key?("week_days")
          Events::RecurrenceRule.build(frequency: merged["frequency"], interval: merged["interval"] || 1, week_days: merged["week_days"],
                                       ends: merged["ends"])
        end

        # The continuation that took the series over, nil when it changed in
        # place. Its days are new on every calendar that showed the series,
        # and the old series' days from today on are gone from them, so
        # those calendars reload whole.
        def reschedule!(applier)
          event = record.event
          result = Events::Reschedule.call(event, rrule: merged_rule(event), slots: @given["slots"])
          fail!("the new repeat never happens") if result.failure?
          return if result.series.equal?(event)

          applier.defer([ -> { Calendar::Refresh.call(*result.series.audience) } ])
          result.series
        end
      end
    end
  end
end
