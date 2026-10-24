# frozen_string_literal: true

module Occurrences
  class FormSave
    # A meal out gets its cost; an eaten meal whose recipes changed empties
    # the pantry again for the corrected amount.
    class Meal < FormSave
      def self.kind = ::Meal
      def self.details_fields = [ :kind, :meal_type, { meal_recipes_attributes: [ %i[id recipe_id _destroy] ] } ]
      def self.cost? = true

      private

      def prepare_update
        @was_completed = record.completed?
      end

      def after_save!
        ::Meal::Consumption.new(record).resync! if updating? && @was_completed && record.completed?
        sync_cost!(title: event.cost_title(record), category: event.fee_category, counterpart: event.cost_counterpart(record)) unless record.details.home?
      end
    end
  end
end
