# frozen_string_literal: true

module Assistant
  module ChangeSets
    class Undoer
      # A reference range as it was, or gone when the set added it; the
      # values that took its unit give it back, and a unit or analyte the
      # set added goes too, once nothing uses it. A unit knows everything
      # that uses it and refuses to go while anything does.
      class SetRange < Step
        def undo!
          LabTestResultEntry.where(id: entry["adopted_entry_ids"]).update_all(unit_id: nil) if entry["adopted_entry_ids"].present?
          range = ReferenceRange.where(analyte: profile.analytes).find_by(id: entry["range_id"])
          if range
            authorize(range, :destroy?)
            entry["created_range"] ? range.destroy! : range.update!(entry["previous"])
          end
          Unit.where(id: entry["unit_id"]).find_each(&:destroy)
          Analyte.where(id: entry["analyte_id"], profile: profile).find_each { |analyte| analyte.destroy! if unused?(analyte) }
        end

        private

        def unused?(analyte) = analyte.reference_ranges.none? && analyte.lab_test_result_entries.none?
      end
    end
  end
end
