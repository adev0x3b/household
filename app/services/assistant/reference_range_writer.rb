# frozen_string_literal: true

# Saves one reference range for a profile, from bounds or from the user's
# own words, and reports what it did in terms the model can pass on. A
# change set checks every operation before it writes any, so the range is
# planned first (#plan) and saved once the whole set is ready (#apply). It
# raises ArgumentError, worded for the model, when the input can't be used.
module Assistant
  class ReferenceRangeWriter
    BOUNDS = %w[low high critical_low critical_high].freeze
    IMPLAUSIBLE_FACTOR = 10

    # Everything checked, nothing written: the range with its new bounds
    # (validated), the analyte and unit rows (possibly new, unsaved), and the
    # bounds it had before (nil for a new range).
    Plan = Data.define(:range, :analyte, :unit, :previous, :bounds, :catalog)

    def initialize(profile)
      @profile = profile
    end

    # `catalog`: the change set's shared Assistant::LabCatalog, so an analyte
    # new to both a lab result and its range is created once.
    def plan(analyte:, unit:, bounds: {}, range_text: nil, sex: nil, catalog: nil)
      # The user's words win over the numbers when both are given, because
      # models add bounds nobody said (a critical_low next to "normal 8.5-10").
      read = RangeText.parse(range_text).transform_keys(&:to_s)
      chosen = read.any? ? read : bounds.to_h.transform_keys(&:to_s).slice(*BOUNDS)
      chosen = BOUNDS.to_h { |key| [ key, number(chosen[key]) ] }
      if chosen.values.all?(&:nil?)
        raise ArgumentError, "no range found#{" in #{range_text.inspect}" if range_text.present?}; " \
                             "pass low, high, critical_low or critical_high as numbers"
      end

      catalog ||= LabCatalog.new(@profile)
      analyte_row = catalog.analyte(analyte)
      unit_row = catalog.unit(unit)

      sex = Normalize.enum(sex).presence || "any"
      raise ArgumentError, "sex must be one of #{ReferenceRange.sexes.keys.join(", ")}" unless ReferenceRange.sexes.key?(sex)

      range = existing(analyte_row, unit_row, sex) || ReferenceRange.new(analyte: analyte_row, unit: unit_row, sex: sex)
      previous = range.persisted? ? range.slice(*BOUNDS).transform_values { |v| v&.to_f } : nil
      Pundit.authorize(@profile, range, range.persisted? ? :update? : :create?)
      range.assign_attributes(chosen)
      range.validate!
      Plan.new(range: range, analyte: analyte_row, unit: unit_row, previous: previous, bounds: chosen.compact, catalog: catalog)
    end

    # Saves a plan. `undo` holds what reverting needs.
    def apply(plan)
      # Checked again here: a lab result earlier in the same set may have
      # saved this very analyte or unit object already.
      created_analyte = plan.analyte.new_record?
      created_unit = plan.unit.new_record?
      created_range = plan.range.new_record?
      adopted = []
      ActiveRecord::Base.transaction do
        plan.analyte.save! if created_analyte
        plan.unit.save! if created_unit
        plan.range.save!
        adopted = adopt_unit(plan.analyte, plan.unit)
      end

      {
        range: { analyte: plan.analyte.name, unit: plan.unit.name, sex: plan.range.sex }.merge(plan.bounds),
        understood: Resources.range_text(plan.range),
        replaced: plan.previous&.compact,
        created_analyte: (plan.analyte.name if created_analyte),
        created_unit: (plan.unit.name if created_unit),
        unit_added_to: adopted.map(&:last).presence,
        values_now: recent_flags(plan.analyte, plan.unit),
        check: [ *implausible(plan.analyte, low: plan.range.low, high: plan.range.high, unit: plan.unit),
                 *other_units_note(plan.analyte, plan.unit) ].presence,
        undo: { "range_id" => plan.range.id, "previous" => plan.previous, "created_range" => created_range,
                "analyte_id" => (plan.analyte.id if created_analyte), "unit_id" => (plan.unit.id if created_unit),
                "adopted_entry_ids" => adopted.map(&:first) }
      }.compact
    end

    # Values ten times past the range ("Calcium 300" against 8.5-10) are far
    # likelier a typo or an OCR slip than a reading, so the model is asked to
    # fix them (the user may have just said the right value) or to ask.
    # Without a unit (a range still waiting for one), the latest values in
    # any unit are read.
    def implausible(analyte, low:, high:, unit: nil)
      low = Float(Normalize.amount(low), exception: false) if low
      high = Float(Normalize.amount(high), exception: false) if high
      return [] unless analyte&.persisted? && (high&.positive? || low&.positive?)

      entries = accessible_entries(analyte).joins(:occurrence).includes(:occurrence, :unit)
      entries = entries.where(unit: unit) if unit
      entries.order("occurrences.date DESC").limit(5).filter_map do |entry|
        value = Float(Normalize.amount(entry.value), exception: false)
        next unless value
        next unless (high&.positive? && value >= high * IMPLAUSIBLE_FACTOR) || (low&.positive? && value <= low / IMPLAUSIBLE_FACTOR)

        "#{analyte.name} #{[ entry.value, entry.unit&.name ].compact.join(" ")} (lab_test_result id #{entry.occurrence_id}, " \
          "#{entry.occurrence.date}) is ten times outside this range — likely a typo. If the user gave " \
          "the right value, fix it now with update_record (values); otherwise ask them."
      end
    end

    private

    def existing(analyte, unit, sex)
      return unless analyte.persisted? && unit.persisted?

      ReferenceRange.where(analyte: @profile.analytes).find_by(analyte: analyte, unit: unit, sex: sex)
    end

    def number(value)
      return if value.nil? || value.to_s.strip.empty?

      number = Float(Normalize.amount(value), exception: false)
      raise ArgumentError, "#{value.inspect} is not a number" unless number

      number
    end

    # The user's values of this analyte recorded without a unit take the
    # range's unit (a report's values and its ranges share units). Values in
    # another unit are left alone and pointed out in `check`.
    def adopt_unit(analyte, unit)
      accessible_entries(analyte).where(unit_id: nil).includes(:occurrence).map do |entry|
        entry.update!(unit: unit)
        [ entry.id, "#{entry.occurrence.date} #{analyte.name} #{entry.value} #{unit.name}" ]
      end
    end

    def accessible_entries(analyte)
      LabTestResultEntry.where(analyte: analyte, occurrence_id: Resources.fetch("lab_test_result").accessible(@profile).select(:id))
    end

    def values_in_other_units(analyte, unit)
      accessible_entries(analyte).joins(:occurrence).includes(:occurrence, :unit)
        .where.not(unit_id: nil).where.not(unit_id: unit.id)
        .order("occurrences.date DESC").limit(5)
        .map { |e| "lab_test_result id #{e.occurrence_id} on #{e.occurrence.date}: #{e.value} #{e.unit.name}" }
    end

    def other_units_note(analyte, unit)
      unmatched = values_in_other_units(analyte, unit)
      return [] if unmatched.empty?

      [ "Some #{analyte.name} values are in another unit, so this range doesn't apply to them: #{unmatched.join("; ")}. " \
        "If the user corrected them, call update_record for that lab result with values." ]
    end

    # How the user's latest values of this analyte now compare to the range.
    def recent_flags(analyte, unit)
      accessible_entries(analyte).where(unit: unit).joins(:occurrence).includes(:occurrence)
        .order("occurrences.date DESC").limit(5)
        .map { |e| "#{e.occurrence.date} #{analyte.name} #{e.value} #{unit.name}: #{e.flag || "no flag"}" }
    end
  end
end
