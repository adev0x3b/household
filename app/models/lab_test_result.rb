# frozen_string_literal: true

# A lab report: its values (LabTestResultEntry) live on the day they were
# measured. Healthcare.
class LabTestResult < Event
  has_details "LabTestResult::Details"

  validates :title, presence: true

  def self.section = :healthcare
  def self.fee_category = :healthcare

  # A report lists each analyte once.
  def validate_occurrence(day)
    active = day.lab_test_result_entries.reject(&:marked_for_destruction?)
    duplicates = active.filter_map(&:analyte_id).tally.select { |_, count| count > 1 }.keys
    return if duplicates.empty?

    names = Analyte.where(id: duplicates).pluck(:name)
    day.errors.add(:lab_test_result_entries, :duplicate_analytes, names: names.join(", "))
  end

  # A card reads its day's values and flags them against their ranges.
  def self.preload_for_cards(days)
    saved = days.select(&:persisted?)
    ActiveRecord::Associations::Preloader.new(records: saved, associations: { lab_test_result_entries: %i[analyte unit] }).call
    LabTestResultEntry.preload_reference_ranges(saved.flat_map(&:lab_test_result_entries))
  end
end
