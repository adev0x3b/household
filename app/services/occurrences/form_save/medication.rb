# frozen_string_literal: true

module Occurrences
  class FormSave
    # A dose's "Taken at" arrives in the actor's zone; what a taken dose
    # used is drawn again from the cupboard when its planned uses change.
    class Medication < FormSave
      def self.kind = ::Medication
      def self.details_fields = [ :kind, :area, :side, :quantity, :unit, :pill_count, { supply_uses_attributes: [ %i[id supply_id quantity _destroy] ] } ]

      def attributes
        @medication_attributes ||= super.tap do |fields|
          fields[:completed_at] = actor.zone.parse(fields[:completed_at]) if fields[:completed_at].is_a?(String) && fields[:completed_at].present?
        end
      end

      private

      def prepare_update
        @was_completed = record.completed?
      end

      def after_save!
        ::Medication::Stock.new(record).resync! if updating? && @was_completed && record.completed?
      end
    end
  end
end
