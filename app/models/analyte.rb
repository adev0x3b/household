# frozen_string_literal: true

class Analyte < ApplicationRecord
  include IdempotentlyNamed
  include Searchable

  searchable_by :name

  STANDARD_NAMES = [ "Glucose", "Cholesterol", "TSH" ].freeze

  belongs_to :profile
  names_unique_within :profile_id

  scope :accessible_by, ->(profile) { where(profile_id: profile.id) }

  # The names a lab value's field suggests: the person's analytes, by name.
  def self.names_for(profile) = accessible_by(profile).order(:name).pluck(:name)

  # The results recorded against it are history, and keep it; its ranges
  # describe it, and go with it.
  has_many :lab_test_result_entries, dependent: :restrict_with_error
  has_many :reference_ranges, dependent: :destroy
  has_many :aliases, class_name: "AnalyteAlias", dependent: :destroy

  # A new member's first analytes, in one insert: a name they have already
  # (in any case) is left as it is, by the unique index on lower(name).
  def self.seed_standards_for!(profile)
    insert_all(STANDARD_NAMES.map { |name| { profile_id: profile.id, name: name } }, unique_by: :index_analytes_on_profile_id_and_lower_name)
  end
end
