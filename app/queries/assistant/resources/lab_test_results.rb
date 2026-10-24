# frozen_string_literal: true

module Assistant
  module Resources
    class LabTestResults < CalendarResource
      def key = "lab_test_result"
      def type = LabTestResult
      def lab_values? = true
      def search_columns = %i[title notes]
      def writable = %w[title notes date]

      # A report is also found by the analytes in it.
      def search_also(matching) = LabTestResultEntry.joins(:analyte).where(matching.call(%w[analytes.name])).select(:occurrence_id)

      def summaries(reports, _profile)
        reports.map { |report| { title: report.title, values: report.persisted? ? lab_values(report) : nil } }
      end

      private

      # Every value of the page's reports, with the ranges that flag them.
      def read_for_summaries(reports)
        super
        load(reports.select(&:persisted?), lab_test_result_entries: %i[analyte unit])
        LabTestResultEntry.preload_reference_ranges(reports.select(&:persisted?).flat_map(&:lab_test_result_entries))
      end
    end
  end
end
