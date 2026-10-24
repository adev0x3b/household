# frozen_string_literal: true

module Assistant
  module ChangeSets
    class Undoer
      # One entry of a change set's undo log, undone (Undoer::STEPS has one
      # for each kind of entry an operation writes).
      class Step
        def initialize(entry, undoer)
          @entry = entry
          @undoer = undoer
        end

        # Undoes the entry. A record that went since (deleted by hand, or
        # with its series) leaves nothing to undo.
        def undo!
          target = record
          revert(target) if target
        end

        private

        attr_reader :entry

        def revert(_record) = raise(NotImplementedError, "#{self.class} must undo its entry")

        # The entry's record, nil when it is gone (Undoer#record_for).
        def record = @undoer.record_for(entry)
        def profile = @undoer.profile
        def refresh(event) = @undoer.refresh(event)
        def authorize(record, query, **options) = Pundit.authorize(profile, record, query, **options)
        def authorize_series(event) = authorize(event, :update?, policy_class: EventPolicy)

        # The series' start, rule and slots as they were.
        def restore_series(event, before)
          event.update!(starts_on: Date.iso8601(before["starts_on"]), rrule: before["rrule"])
          event.assign_slots(Array(before["slots"]))
        end
      end
    end
  end
end
