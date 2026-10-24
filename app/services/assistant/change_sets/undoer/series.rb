# frozen_string_literal: true

module Assistant
  module ChangeSets
    class Undoer
      # A series' repeat as it was. When the change split the series, the
      # new series goes by its own "created" entry.
      class Series < Step
        private

        def revert(event)
          authorize_series(event)
          restore_series(event, entry["event_before"])
          refresh(event)
        end
      end
    end
  end
end
