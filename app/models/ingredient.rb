# frozen_string_literal: true

class Ingredient < ApplicationRecord
  include IdempotentlyNamed
  include Searchable

  searchable_by :name

  # The store section it is found in, so a grocery list can be walked aisle
  # by aisle. Icons live in Views::Ingredients::Category, names in
  # `ingredients.category.*`.
  enum :category, { other: 0, produce: 1, dairy_eggs: 2, meat_fish: 3, bakery: 4, pantry: 5, frozen_foods: 6, drinks: 7, household: 8 }

  # The order the sections come in a typical walk through a shop; "other" last.
  CATEGORY_ORDER = %w[produce bakery dairy_eggs meat_fish pantry frozen_foods drinks household other].freeze

  belongs_to :profile
  names_unique_within :profile_id
  belongs_to :unit, optional: true

  scope :accessible_by, ->(profile) { where(profile_id: profile.id) }

  # The names an ingredient field suggests: the pantry's, by name.
  def self.names_for(profile) = accessible_by(profile).order(:name).pluck(:name)

  has_many :recipe_ingredients, dependent: :restrict_with_error
  has_many :grocery_list_items, dependent: :restrict_with_error
  has_many :ingredient_purchases, dependent: :destroy
  has_many :meal_consumptions, dependent: :destroy

  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates_within_household :unit, of: :profile

  # The unit as typed on the form, one of the household's.
  def unit_name=(name)
    type_name(:unit, name) { { household_id: profile.household_id } }
  end

  # Stock moves by what was bought or given back, never below nothing on the
  # shelf: a purchase deleted after the food was eaten can't make it negative.
  # The sum is taken in the database, from the quantity as it is there, so
  # two changes at once (two people ticking off one list) both count. This
  # copy moves by the same change, as Rails' own increment! does, without
  # reading the row back: the row is the truth.
  def adjust_stock!(delta)
    now = Time.current
    self.class.where(id: id).update_all([ "quantity = GREATEST(quantity + ?, 0), updated_at = ?", delta, now ])
    self.quantity = [ quantity + delta, 0 ].max
    self.updated_at = now
    clear_attribute_changes(%w[quantity updated_at])
  end
end
