# frozen_string_literal: true

module Occurrences
  class FormSave
    # What the form changes against what the day read when the form was
    # built: each universal field and each of the kind's own, the day's own
    # value else the series'. Built before the save assigns anything, since
    # a save (or a hold checking it would save) writes the form onto these
    # same records before it asks what changed.
    class Changes
      def initialize(record, submitted:, details_fields:)
        @record = record
        @submitted = submitted.to_h
        details = record.details
        @saved = FIELDS.to_h { |field| [ field.to_s, record.public_send(field) ] }
        @saved_details = details_fields.to_h { |field| [ field.to_s, details&.public_send(field) ] }
      end

      # The fields whose value differs, the status when it changes with what
      # travels with it, and every nested list as sent.
      def to_h
        @to_h ||= begin
          plain = @submitted.reject { |key, _| key.end_with?("_attributes") || key == "status" || STATUS_DETAILS.include?(key) }
          changes = plain.reject { |key, value| same_value?(as_read(key, value), saved(key)) }
          details = (@submitted["details_attributes"] || {}).select do |key, value|
            key.end_with?("_attributes") || !same_value?(details_as_read(key, value), saved_details(key))
          end
          changes["details_attributes"] = details if details.any?
          changes["status"] = @submitted["status"] if @submitted["status"].present? && @submitted["status"] != @record.status
          STATUS_DETAILS.each { |key| changes[key] = @submitted[key] if @submitted[key].present? && changes.key?("status") }
          changes.merge(@submitted.select { |key, _| key.end_with?("_attributes") && key != "details_attributes" })
        end
      end

      # A field's value as saved: the day's own when it has one, else the series'.
      def saved(key) = @saved[key.to_s]
      def saved_details(field) = @saved_details[field.to_s]

      private

      # The form sends text and what is saved is typed (a time of day, a
      # decimal), so each value sent is read the way the model reads it
      # once assigned: "14:00" is the saved 14:00 and "50" a saved 50.0.
      def as_read(key, value) = @record.class.type_for_attribute(key).cast(value)

      def details_as_read(field, value)
        @record.event.class.details_class.new(field => value).public_send(field)
      end

      # An empty field is the same as none.
      def same_value?(submitted, saved) = blank_as_nil(submitted) == blank_as_nil(saved)
      def blank_as_nil(value) = value.is_a?(String) && value.empty? ? nil : value
    end
  end
end
