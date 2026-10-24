# frozen_string_literal: true

module Assistant
  module Resources
    class Analytes < Resource
      def key = "analyte"
      def model = Analyte
      def mergeable? = true
      def search_columns = %i[name]
      def writable = %w[name]

      def scope(profile) = profile.analytes

      def summaries(analytes, _profile)
        analytes.map { |analyte| { name: analyte.name, reference_ranges: analyte.reference_ranges.map { |range| range_text(range) } } }
      end

      private

      def read_for_summaries(analytes)
        super
        load(analytes, reference_ranges: :unit)
      end
    end
  end
end
