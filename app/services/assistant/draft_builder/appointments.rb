# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # A visit of any kind, with its fee when one was said. Some visits are
    # free, so a fee is never asked for; a booked visit needs its time.
    class Appointments < Series
      # A visit is found again by who it is with, two weeks either side.
      DUPLICATE_WINDOW = 14

      # "Visit Moretti 11:00 on 2 October 2026".
      def label = with_date([ series.title, record.formatted_start_time ].compact.join(" "), record.date)

      private

      def cost_section = :optional
      def required_fields = %w[start_time]

      # "Appointment with Moretti": a title is never worth asking for.
      def fill_in(event, _given)
        counterpart = event.details.counterpart
        event.title = I18n.t("assistant.defaults.appointment_title", counterpart: counterpart) if event.title.blank? && counterpart.present?
      end

      def duplicate_query = record.details.counterpart.presence || record.title
      def duplicate_window = DUPLICATE_WINDOW

      # The fee starts pending while the visit is still ahead (it is paid
      # with the visit) and paid for a visit already past.
      def attach_fee(committer, day)
        committer.attach_cost(day, date: day.date, title: series.cost_title(day), counterparty: series.cost_counterpart(day),
                                   status: day.date >= Date.current ? :pending : :completed, category: series.fee_category)
      end
    end
  end
end
