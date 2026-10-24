# frozen_string_literal: true

module Occurrences
  class FormSave
    # Its cost section becomes the visit's fee, filed under the kind's
    # category and named after who it was with.
    class Appointment < FormSave
      def self.kind = ::Appointment
      def self.details_fields = %i[kind counterpart]
      def self.cost? = true

      private

      def after_save!
        sync_cost!(title: event.cost_title(record), counterpart: event.cost_counterpart(record), category: event.fee_category)
      end
    end
  end
end
