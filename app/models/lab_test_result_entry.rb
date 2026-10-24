# frozen_string_literal: true

class LabTestResultEntry < ApplicationRecord
  FLAGS = %i[normal low high abnormal].freeze

  belongs_to :occurrence, inverse_of: :lab_test_result_entries
  belongs_to :analyte
  belongs_to :unit, optional: true

  after_save { occurrence.mark_changed! if saved_changes? }
  after_destroy { occurrence.mark_changed! unless destroyed_by_association }

  validates :value, presence: true
  validates :analyte_id, uniqueness: { scope: :occurrence_id }
  validates_accessible :analyte, by: -> { occurrence&.event&.profile }
  validates_within_household :unit, of: -> { occurrence&.event&.profile }

  # Typed by name into the report owner's catalog, whoever enters the value.
  def analyte_name=(name)
    type_name(:analyte, name) { { profile_id: occurrence.event.profile_id } }
  end

  def unit_name=(name)
    type_name(:unit, name) { { household_id: occurrence.event.profile.household_id } }
  end

  # Normal/Low/High/Abnormal, computed live against the current reference
  # range — never persisted (a later range correction should immediately
  # reflect in how past results are displayed). Returns nil when there's no
  # unit, the value isn't numeric, or nobody has defined a reference range
  # for this analyte+unit — those are all legitimate "can't say" cases, not
  # bugs. Many entries at once (a report, a month of cards) read their
  # ranges in one query first (preload_reference_ranges).
  def flag(range = matching_reference_range)
    return nil unless unit && (number = numeric_value)
    return nil unless range

    if (range.critical_low && number <= range.critical_low) || (range.critical_high && number >= range.critical_high)
      :abnormal
    elsif range.low && number < range.low
      :low
    elsif range.high && number > range.high
      :high
    else
      :normal
    end
  end

  # The value as a number, or nil for a value that is words ("<0.5",
  # "positive"). A report printed in Italian writes "5,4", so a decimal comma
  # reads as a point; the value itself stays as it was typed.
  def numeric_value = Float(value.to_s.tr(",", "."), exception: false)

  # The ranges of many entries' analytes and units in one query: each entry
  # then picks its own among them (by the analyte and unit it has when it
  # is asked; one changed since asks again).
  def self.preload_reference_ranges(entries)
    keys = entries.filter_map { |entry| [ entry.analyte_id, entry.unit_id ] if entry.analyte_id && entry.unit_id }.uniq
    found = keys.index_with { [] }
    if keys.any?
      ReferenceRange.where(analyte_id: keys.map(&:first).uniq, unit_id: keys.map(&:last).uniq).each do |range|
        found[[ range.analyte_id, range.unit_id ]]&.push(range)
      end
    end
    entries.each { |entry| entry.reference_ranges_by_key = found }
  end

  attr_writer :reference_ranges_by_key

  private

  # Prefers a range matching the report owner's sex; falls back to the
  # sex-agnostic ("any") range. A non_binary profile has no direct match by
  # design (reference ranges are biological-sex-based, not identity-based)
  # and always falls back to "any".
  def matching_reference_range
    return nil unless analyte && unit

    gender = occurrence.event.profile.gender
    candidates = @reference_ranges_by_key&.fetch([ analyte_id, unit_id ], nil)
    # Never pass a value ReferenceRange.sex doesn't recognize (e.g. "non_binary")
    # into `where` — filter it out here rather than rely on enum coercion.
    sexes = ReferenceRange.sexes.key?(gender) ? [ gender, "any" ] : [ "any" ]
    candidates ||= ReferenceRange.where(analyte: analyte, unit: unit, sex: sexes).to_a
    ReferenceRange.best_match(candidates, gender)
  end
end
