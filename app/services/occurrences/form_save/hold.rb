# frozen_string_literal: true

module Occurrences
  class FormSave
    # The form as a request that waits for its owner's OK (Links::Approvals::Hold):
    # the data it keeps to be saved later, and the rows the owner is shown.
    class Hold
      def initialize(form)
        @form = form
      end

      # A saved day's form keeps only what it changes, so an approval that
      # comes late doesn't overwrite what the owner changed in between; a
      # new series or a projected day keeps all it was given, and which day
      # it is.
      def payload
        key = @form.class.param_key
        data = { key => (@form.updating? ? @form.changes.to_h : @form.attributes.to_h).dup }
        data[key]["event_id"] = @form.event.id.to_s if @form.materializing?
        data[key]["date"] = @form.record.date.iso8601 if (@form.materializing? || @form.new_series?) && @form.record.date
        data[key]["time"] = @form.record.time_string if @form.materializing? && @form.record.time
        data[key]["apply_to"] = @form.apply_to if @form.apply_to.present?
        data["event"] = @form.series_shape.payload if shape_changes?
        cost = @form.cost_params.to_h.compact_blank
        data["transaction"] = cost if cost.any?
        data.deep_stringify_keys
      end

      # One row per changed value, each as the owner would read it; a list
      # (a day's children, a dose's uses) is not a row.
      def preview
        changes = @form.updating? ? @form.changes.to_h : @form.attributes.to_h.compact_blank
        rows = []
        changes.each do |key, value|
          if key.to_s == "details_attributes" && value.is_a?(Hash)
            value.each { |field, to| rows << row(field, @form.changes.saved_details(field), to) unless to.is_a?(Array) || to.is_a?(Hash) }
          elsif !value.is_a?(Array) && !value.is_a?(Hash)
            rows << row(key, (@form.changes.saved(key) if @form.updating?), value)
          end
        end
        rows << { "attribute" => "recurrence", "from" => nil, "to" => @form.series_shape.frequency.to_s } if shape_changes?
        rows << { "attribute" => "amount", "from" => nil, "to" => @form.cost_params[:amount].to_s } if @form.cost_params[:amount].present?
        rows
      end

      private

      def shape_changes?
        @form.series_shape.submitted? && (!@form.updating? || @form.series_shape.changed_for?(@form.event))
      end

      def row(key, from, to)
        { "attribute" => key.to_s, "from" => shown(key, from), "to" => shown(key, to) }
      end

      def shown(key, value) = LinkApproval.shown(@form.class.kind, key, value)
    end
  end
end
