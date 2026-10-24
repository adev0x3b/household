# frozen_string_literal: true

class GroceryListItem < ApplicationRecord
  include EditedTogether

  belongs_to :grocery_list
  belongs_to :ingredient
  belongs_to :unit, optional: true
  has_many :ingredient_purchases, dependent: :nullify

  # The store section is the ingredient's: a list is grouped by it. The
  # item's form saves it on the ingredient (GroceryListItemsController), and
  # a form shown again shows what was chosen.
  delegate :category, :category=, to: :ingredient, allow_nil: true

  validates :quantity, numericality: { greater_than: 0 }, allow_nil: true
  validates :ingredient_id, uniqueness: { scope: :grocery_list_id }
  validates_accessible :ingredient, by: -> { grocery_list&.profile }
  validates_within_household :unit, of: -> { grocery_list&.profile }

  scope :accessible_by, ->(profile) { where(grocery_list_id: GroceryList.accessible_by(profile).select(:id)) }

  # Typed by name into the list owner's catalog, not the editor's, like a
  # recipe's lines.
  def ingredient_name=(name)
    type_name(:ingredient, name) { { profile_id: grocery_list.profile_id } }
  end

  def unit_name=(name)
    type_name(:unit, name) { { household_id: grocery_list.profile.household_id } }
  end

  # Checking an item off buys it: one IngredientPurchase restocks the ingredient
  # (converting the item's unit into the ingredient's, or raising
  # ActiveRecord::RecordInvalid when they don't convert). Unchecking removes
  # that purchase, which takes the stock back off the shelf. An item with no
  # quantity is only ticked: how much was bought isn't known, so the stock stays.
  #
  # Both read the item again under its row's lock and do nothing when it is
  # already as asked, so a second tap, a housemate's tap on the same item or
  # a page that was out of date never buys it twice or undoes the other.
  def check!
    with_lock do
      next if checked?

      if quantity
        ingredient.ingredient_purchases.create!(
          profile_id: ingredient.profile_id, quantity: quantity, unit: unit,
          purchased_on: Date.current, grocery_list_item: self
        )
      end
      update!(checked: true, checked_at: Time.current)
    end
  end

  def uncheck!
    with_lock do
      next unless checked?

      if ingredient_purchases.any?
        ingredient_purchases.destroy_all
      elsif quantity
        # Checked off before check-offs wrote purchases: give the stock back directly.
        ingredient.adjust_stock!(-(Unit.convert(quantity, unit, ingredient.unit) || 0))
      end
      update!(checked: false, checked_at: nil)
    end
  end
end
