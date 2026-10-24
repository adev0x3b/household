# frozen_string_literal: true

module Assistant
  module Resources
    class Appointments < CalendarResource
      def key = "appointment"
      def type = Appointment
      def search_columns = %i[title counterpart location notes]
      def writable = %w[title counterpart kind start_time location notes date]
      def enums = { "kind" => Appointment::Kind::ALL }

      def summaries(visits, _profile)
        visits.map do |visit|
          { title: visit.title, counterpart: visit.details.counterpart, kind: visit.details.kind, time: visit.formatted_start_time,
            location: visit.location }.merge(cost_fields(visit))
        end
      end
    end
  end
end
