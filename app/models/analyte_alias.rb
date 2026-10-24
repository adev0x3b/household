# frozen_string_literal: true

# Another name of a profile's analyte — what a merged-away analyte was
# called. Unique per profile, like analyte names, and never the name of one
# of the profile's analytes (that name would mean two things).
class AnalyteAlias < ApplicationRecord
  belongs_to :analyte
  belongs_to :profile

  validates :name, presence: true, uniqueness: { scope: :profile_id, case_sensitive: false }
  validate :not_an_analyte_name
  validates_accessible :analyte, by: :profile

  before_validation { self.profile_id ||= analyte&.profile_id }

  private

  def not_an_analyte_name
    return if name.blank? || profile_id.nil?

    errors.add(:name, :taken) if Analyte.where(profile_id: profile_id).exists?([ "LOWER(name) = ?", name.downcase ])
  end
end
