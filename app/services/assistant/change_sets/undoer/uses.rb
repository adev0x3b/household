# frozen_string_literal: true

module Assistant
  module ChangeSets
    class Undoer
      # The supplies a dose plans to use, as they were: a series' (and a
      # one-off taken dose's stock with them), or one day's own list.
      class Uses < Step
        private

        def revert(planned) = planned.is_a?(Occurrence) ? undo_day(planned) : undo_series(planned)

        # A dose's own list, written as it was marked done. Its status is
        # undone first (the log is read newest first), unless it was done
        # already, when its stock follows the list it gets back.
        def undo_day(day)
          authorize(day, :update?)
          refresh(day.event)
          day.own_details.replace_uses!(entry["before"] || [])
          Medication::Stock.new(day).resync! if day.completed?
        end

        def undo_series(event)
          authorize_series(event)
          refresh(event)
          event.details.replace_uses!(entry["before"])
          day = Occurrence.find(entry["day_id"]) if entry["day_id"]
          day.own_details.replace_uses!(entry["day_before"]) if entry["day_before"]
          Medication::Stock.new(day).resync! if entry["resync"]
        end
      end
    end
  end
end
