# frozen_string_literal: true

module Assistant
  module Operations
    # Saves one analyte's reference range. A unit left out is taken from a
    # lab result in the same set, else from what the user just wrote by the
    # analyte's name, else from their latest value, so they are rarely asked.
    class SetRange < Base
      BOUND_ALIASES = { "normal_low" => "low", "min" => "low", "lower" => "low", "normal_high" => "high", "max" => "high",
                        "upper" => "high", "critical_min" => "critical_low", "critical_max" => "critical_high",
                        "critically_low" => "critical_low", "critically_high" => "critical_high",
                        "crit_low" => "critical_low", "crit_high" => "critical_high",
                        "reference" => "range_text", "range" => "range_text", "normal_range" => "range_text",
                        "reference_range" => "range_text", "text" => "range_text", "name" => "analyte",
                        "analyte_name" => "analyte", "unit_name" => "unit", "units" => "unit" }.freeze
      KNOWN = %w[analyte unit sex low high critical_low critical_high range_text].freeze

      # The same analyte and unit is the same range, whatever its bounds.
      def self.same_spec?(a, b) = range_of(a) == range_of(b)

      def self.range_of(spec) = spec["fields"].values_at("analyte", "unit").map { |name| name.to_s.downcase.squish }
      private_class_method :range_of

      def phase = :setting_ranges

      def check
        given = fields.transform_keys { |key| BOUND_ALIASES.fetch(key.to_s, key.to_s) }
        ignored = given.keys - KNOWN
        @notes << "not understood: #{ignored.join(", ")}" if ignored.any?
        analyte = given["analyte"].presence
        if analyte.nil?
          @missing << "analyte"
          return
        end

        unit = given["unit"].presence || context.lab_units[analyte.to_s.downcase] || said_unit(analyte) || latest_unit(analyte)
        if unit.blank?
          # Waiting for a unit needn't hide a value that is plainly a typo.
          @notes.concat(ReferenceRangeWriter.new(profile).implausible(context.lab_catalog.known_analyte(analyte.to_s),
                                                                      low: given["low"], high: given["high"]))
          @missing << "unit (for #{analyte})"
          return
        end

        @writer = ReferenceRangeWriter.new(profile)
        @plan = @writer.plan(analyte: analyte, unit: unit, bounds: given.slice(*ReferenceRangeWriter::BOUNDS),
                             range_text: given["range_text"], sex: given["sex"], catalog: context.lab_catalog)
      end

      def apply!(applier)
        # The analyte may have been saved by a lab result earlier in this set.
        data = @writer.apply(@plan)
        applier.saved([ data.except(:undo) ])
        [ { "kind" => "range" }.merge(data[:undo]) ]
      end

      # "Cobalamin (pg/mL): low 150, high 250, critical at 80 / 300", localized.
      def label
        return super unless @plan

        range = @plan.range
        parts = ReferenceRangeWriter::BOUNDS.filter_map do |bound|
          value = range[bound]
          next if value.nil?

          I18n.t("assistant.operations.bounds.#{bound}",
                 value: ActiveSupport::NumberHelper.number_to_rounded(value, precision: 3, significant: true, strip_insignificant_zeros: true, locale: I18n.locale))
        end
        "#{@plan.analyte.name} (#{@plan.unit.name}): #{parts.join(", ")}"
      end

      private

      def said_unit(analyte)
        return unless context.chat

        said = context.chat.assistant_messages.where(role: "user").order(:created_at, :id).last&.content
        UnitName.said_for(said, analyte)
      end

      def latest_unit(name)
        analyte = context.lab_catalog.analyte(name)
        return unless analyte.persisted?

        LabTestResultEntry.where(analyte: analyte).where.not(unit_id: nil).order(id: :desc).first&.unit&.name
      end
    end
  end
end
