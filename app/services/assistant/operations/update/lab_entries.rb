# frozen_string_literal: true

module Assistant
  module Operations
    class Update < Base
      # A lab result's values to fix, add or drop. The day's entries are kept
      # whole for the undo, since one call can touch several of them.
      class LabEntries < Part
        def initialize(record, entries:, remove:, context:)
          super(record, profile: context.profile)
          @entries = entries
          @remove = remove
          @context = context
        end

        def any? = @entries.any? || @remove.any?

        # An upcoming day has no values yet: undo then takes away the ones
        # this change gave it before the day goes back to unsaved.
        def before = { lab_before: record.lab_test_result_entries.map { |entry| entry.slice(:analyte_id, :unit_id, :value) } }

        def apply!(_applier)
          LabValues.apply!(record, entries: @entries, remove: @remove, catalog: @context.lab_catalog_for(record.event.profile))
          []
        end
      end
    end
  end
end
