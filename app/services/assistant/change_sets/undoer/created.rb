# frozen_string_literal: true

module Assistant
  module ChangeSets
    class Undoer
      # What the set created goes: a series (its first day, or the series
      # itself) with everything in it, a purchase, a supply nobody bought.
      class Created < Step
        private

        def revert(created)
          case created
          when Supply
            created.destroy! if created.supply_purchases.none?
          when Occurrence
            days_unchanged!(created.event)
            Occurrences::Destroy.call(created, by: profile, scope: "series")
          when Event
            days_unchanged!(created)
            Occurrences::Destroy.call(created.first_occurrence, by: profile, scope: "series")
          else
            authorize(created, :destroy?)
            created.destroy!
          end
        end

        # A series goes with every day in it, so none of them may have
        # changed since (a day done, a value recorded): a day's change
        # doesn't touch its series, which Undoer#record_for checked.
        def days_unchanged!(event)
          latest = event.occurrences.order(updated_at: :desc).first
          @undoer.unchanged_since!(latest, latest.updated_at, entry["updated_at"]) if latest
        end
      end
    end
  end
end
