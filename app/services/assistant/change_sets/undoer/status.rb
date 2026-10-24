# frozen_string_literal: true

module Assistant
  module ChangeSets
    class Undoer
      # Back to the status it had (Occurrence#change_status! reverses stock
      # and costs); an upcoming day this set saved goes back to unsaved.
      class Status < Step
        private

        def revert(day)
          authorize(day, :change_status?)
          refresh(day.event)
          if entry["materialized"]
            day.change_status!("pending") unless day.pending?
            day.destroy!
          else
            day.change_status!(entry["from"])
          end
        end
      end
    end
  end
end
