# frozen_string_literal: true

class Unit < ApplicationRecord
  include IdempotentlyNamed

  belongs_to :household
  names_unique_within :household_id

  # The household's own vocabulary: what its members typed, nobody else's.
  scope :accessible_by, ->(profile) { where(household_id: profile.household_id) }

  # What a form offers: the names a quantity field suggests, and the units a
  # select picks from, as [ name, id ].
  def self.names_for(profile) = accessible_by(profile).order(:name).pluck(:name)
  def self.choices_for(profile) = accessible_by(profile).order(:name).pluck(:name, :id)

  has_many :lab_test_result_entries, dependent: :restrict_with_error
  has_many :reference_ranges, dependent: :restrict_with_error
  has_many :ingredients, dependent: :restrict_with_error
  has_many :recipe_ingredients, dependent: :restrict_with_error
  has_many :grocery_list_items, dependent: :restrict_with_error
  has_many :ingredient_purchases, dependent: :restrict_with_error

  # Units a kitchen mixes freely: name => [ family, size in the family's base unit ].
  FAMILIES = {
    "mg" => [ :mass, 0.001 ], "g" => [ :mass, 1 ], "kg" => [ :mass, 1000 ],
    "ml" => [ :volume, 1 ], "cl" => [ :volume, 10 ], "dl" => [ :volume, 100 ], "l" => [ :volume, 1000 ]
  }.freeze

  # `quantity` expressed in `to` instead of `from`. A missing unit on either
  # side is taken at face value; two different units that don't convert (g to
  # pcs) give nil, so callers refuse rather than add apples to kilograms.
  def self.convert(quantity, from, to)
    return quantity if from.nil? || to.nil? || from == to

    from_family, from_size = FAMILIES[from.name.to_s.strip.downcase]
    to_family, to_size = FAMILIES[to.name.to_s.strip.downcase]
    return unless from_family && from_family == to_family

    (BigDecimal(quantity.to_s) * BigDecimal(from_size.to_s) / BigDecimal(to_size.to_s)).round(3)
  end
end
