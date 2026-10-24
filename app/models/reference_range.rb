# frozen_string_literal: true

class ReferenceRange < ApplicationRecord
  belongs_to :analyte
  belongs_to :unit

  enum :sex, { any: 0, male: 1, female: 2 }

  # The range for everyone first, then each sex's.
  scope :by_sex, -> { order(:sex) }

  validates :sex, uniqueness: { scope: [ :analyte_id, :unit_id ] }
  validate :at_least_one_bound_present
  validates_within_household :unit, of: -> { analyte&.profile }
  validate :bounds_are_ordered

  # Prefers a range matching the profile's gender, then falls back to the
  # sex-agnostic ("any") range. A non_binary profile has no direct match by
  # design (reference ranges are biological-sex-based, not identity-based)
  # and always falls back to "any". `candidates` are the ranges for one
  # analyte+unit pair.
  def self.best_match(candidates, gender)
    candidates.find { |range| range.sex == gender } || candidates.find { |range| range.sex == "any" }
  end

  private

  def at_least_one_bound_present
    return if [ low, high, critical_low, critical_high ].any?(&:present?)

    errors.add(:base, :blank_bounds)
  end

  def bounds_are_ordered
    errors.add(:low, :must_be_less_than_high) if low && high && low >= high
    errors.add(:critical_low, :must_be_less_than_low) if critical_low && low && critical_low > low
    errors.add(:critical_high, :must_be_greater_than_high) if critical_high && high && critical_high < high
  end
end
