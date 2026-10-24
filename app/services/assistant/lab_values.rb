# frozen_string_literal: true

# Corrects the values of a lab result's day, matching each given value to
# the entry for the same analyte. A projected day is saved first, because
# its values hang off its row. Returns the analytes updated, added and
# removed.
module Assistant
  module LabValues
    module_function

    def apply!(result, entries:, remove: [], catalog:)
      changes = { updated: [], added: [], removed: [] }
      result.materialize!

      added = []
      entries.each do |given|
        analyte = catalog.analyte(given["analyte_name"])
        unit = catalog.unit(given["unit_name"])
        entry = result.lab_test_result_entries.find { |e| same_analyte?(e.analyte, analyte) }

        if entry
          entry.update!({ value: given["value"], unit: unit }.compact)
          changes[:updated] << analyte.name
        else
          added << result.lab_test_result_entries.build(analyte: analyte, unit: unit, value: given["value"])
          changes[:added] << analyte.name
        end
      end
      LabTestResultEntry.read_access(added)
      added.each(&:save!)

      Array(remove).each do |name|
        analyte = catalog.analyte(name)
        entry = result.lab_test_result_entries.find { |e| same_analyte?(e.analyte, analyte) }
        next unless entry

        entry.destroy!
        changes[:removed] << entry.analyte.name
      end

      changes.reject { |_, names| names.empty? }
    end

    def same_analyte?(a, b)
      a.persisted? && b.persisted? ? a.id == b.id : a.name.casecmp?(b.name)
    end
  end
end
