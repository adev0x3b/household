# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # A lab report and its values. Each analyte and unit is the matching
    # catalog row (Assistant::NameMatch) or a new unsaved one, created only
    # when the report is saved; one without any value is never worth saving.
    class LabTestResults < Series
      # The same report logged twice (once with today's date, then again
      # with the day the test was done): the same values within this many days.
      VALUES_WINDOW = 45

      def lab_entries
        @lab_entries ||= Array(draft.payload["entries"]).map do |entry|
          analyte = lab_catalog.analyte(entry["analyte_name"])
          LabTestResultEntry.new(analyte: analyte, unit: lab_catalog.unit(entry["unit_name"]) || range_unit(analyte), value: entry["value"].to_s)
        end
      end

      def new_analyte_names = lab_entries.map(&:analyte).reject(&:persisted?).map(&:name)

      # The units the user gave for its analytes, for a range in the same set that names none.
      def lab_units = lab_entries.filter_map { |entry| [ entry.analyte.name.downcase, entry.unit.name ] if entry.unit }.to_h

      def missing_parts
        lab_entries.empty? ? super + [ { "field" => "lab_test_result.entries" } ] : super
      end

      def duplicates = super + same_values

      def notes
        notes = []
        notes << "new analytes: #{new_analyte_names.join(", ")}" if new_analyte_names.any?
        notes << "some values have no unit" if lab_entries.any? { |entry| entry.unit.nil? }
        notes
      end

      # "Lab results (4 values) on 16 September 2026".
      def label = with_date("#{series.title || type_label} (#{I18n.t("assistant.operations.values", count: lab_entries.size)})", record.date)

      private

      def build
        day = super
        lab_entries.each { |entry| day.lab_test_result_entries << entry }
        day
      end

      def fill_in(event, _given)
        event.title = I18n.t("assistant.defaults.lab_test_result_title") if event.title.blank? && lab_entries.any?
      end

      # A value without a unit takes the unit of the analyte's reference
      # range when it has exactly one, as ranges saved later adopt unit-less
      # values (Assistant::ReferenceRangeWriter).
      def range_unit(analyte)
        return unless analyte.persisted?

        units = analyte.reference_ranges.map(&:unit).uniq
        units.one? ? units.first : nil
      end

      # Reports around its date that share more than half of its values.
      def same_values
        date = record.date
        return [] if lab_entries.empty? || date.nil?

        wanted = lab_entries.to_set { |entry| [ entry.analyte.name.downcase, entry.value.to_s ] }
        resource.accessible(profile).where(date: (date - VALUES_WINDOW)..(date + VALUES_WINDOW))
          .includes(lab_test_result_entries: :analyte).select do |report|
            have = report.lab_test_result_entries.to_set { |entry| [ entry.analyte.name.downcase, entry.value.to_s ] }
            (wanted & have).size * 2 > wanted.size
          end.map { |report| summarize(report) }
      end
    end
  end
end
