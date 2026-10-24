# frozen_string_literal: true

module Assistant
  module Resources
    class Medications < CalendarResource
      def key = "medication"
      def type = Medication
      def search_columns = %i[title]
      def writable = %w[title kind area side quantity unit pill_count date time anchor skipped_reason completed_at]
      def doses? = true

      def enums
        { "kind" => Medication::Details.kinds.keys, "area" => Medication::Details.areas.keys, "side" => Medication::Details.sides.keys,
          "skipped_reason" => Medication.skip_reasons, "anchor" => Events::TimesOfDay::ANCHORS.keys }
      end

      # A dose's supplies come with its details (Medication::Details.preloads).
      def summaries(doses, _profile)
        doses.map do |dose|
          details = dose.details
          { title: dose.title, kind: details.kind, dose: details.dose_label, area: details.area, side: details.side,
            reason: dose.skipped_reason, uses: supply_uses(dose).presence }
        end
      end
    end
  end
end
