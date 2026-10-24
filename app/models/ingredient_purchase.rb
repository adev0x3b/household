# frozen_string_literal: true

# Something bought for the pantry: adds to the ingredient's stock and may carry
# the single cost Transaction (category groceries). Quantities are kept in the
# ingredient's own unit, converting g/kg and ml/l on the way in.
class IngredientPurchase < ApplicationRecord
  include Costable

  belongs_to :ingredient
  belongs_to :profile
  belongs_to :unit, optional: true
  belongs_to :grocery_list_item, optional: true

  before_validation :default_unit, on: :create
  before_validation :convert_to_ingredient_unit, on: :create

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :purchased_on, presence: true
  validate :unit_matches_ingredient
  validates_accessible :ingredient, by: :profile
  validates_accessible :grocery_list_item, by: :profile
  validates_within_household :unit, of: :profile

  # While a purchase exists, what it bought is on the shelf. Callbacks keep
  # that true for every writer, including those that save any kind of record
  # alike and couldn't move a shelf without asking what they hold. An
  # ingredient going away takes its shelf with it, so its purchases give
  # nothing back.
  after_create { ingredient.adjust_stock!(quantity) }
  after_update :adjust_stock_for_quantity_change, if: :saved_change_to_quantity?
  after_destroy { ingredient.adjust_stock!(-quantity) unless destroyed_by_association }

  scope :accessible_by, ->(profile) { where(profile_id: profile.id) }
  scope :latest_first, -> { order(purchased_on: :desc, id: :desc) }

  def cost_category = :groceries

  # The unit typed for what was bought. Only a purchase being made takes
  # one: once saved, its quantity is kept in the ingredient's unit, and a
  # unit that converts into it (grams of flour kept in kilograms) is never
  # added to the household's.
  def unit_name=(name)
    return unless new_record?

    type_name(:unit, name) { { household_id: profile&.household_id } }
  end

  # "Flour × 1 kg", for messages that name this purchase.
  def event_label
    amount = quantity == quantity.to_i ? quantity.to_i.to_s : quantity.to_s
    "#{ingredient.name} × #{[ amount, unit&.name ].compact_blank.join(" ")}"
  end

  # Title of the cost transaction. "2" rather than "2.0", the way a person says it.
  def cost_title
    amount = quantity == quantity.to_i ? quantity.to_i.to_s : quantity.to_s
    I18n.t("ingredient_purchases.form.transaction_title",
           quantity: [ amount, unit&.name ].compact_blank.join(" "), ingredient_name: ingredient.name)
  end

  private

  def default_unit
    self.unit ||= ingredient&.unit
  end

  def convert_to_ingredient_unit
    return unless ingredient && quantity.present?

    converted = Unit.convert(quantity, unit, ingredient.unit) or return
    self.quantity = converted
    self.unit = ingredient.unit if ingredient.unit
  end

  # Whatever convert_to_ingredient_unit couldn't bring into the ingredient's
  # unit (grams of something counted in pieces) is refused, not guessed at.
  def unit_matches_ingredient
    return unless ingredient&.unit && unit && unit_id != ingredient.unit_id

    errors.add(:unit, :not_convertible, ingredient_unit: ingredient.unit.name)
  end

  def adjust_stock_for_quantity_change
    ingredient.adjust_stock!(quantity - quantity_before_last_save)
  end
end
