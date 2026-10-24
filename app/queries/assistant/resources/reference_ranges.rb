# frozen_string_literal: true

module Assistant
  module Resources
    # Written only through set_reference_ranges, deleted through
    # delete_records: an update would need to say which of an analyte's
    # ranges it means.
    class ReferenceRanges < Resource
      def key = "reference_range"
      def model = ReferenceRange
      def search_columns = %w[analytes.name]
      def writable = []

      def scope(profile) = ReferenceRange.where(analyte: profile.analytes).joins(:analyte)
      def readers(range) = [ range.analyte.profile ]

      def summaries(ranges, _profile)
        ranges.map { |range| { analyte: range.analyte.name, range: range_text(range) } }
      end

      private

      def read_for_summaries(ranges)
        super
        load(ranges, :analyte, :unit)
      end
    end
  end
end
