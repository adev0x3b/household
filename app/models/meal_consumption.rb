# frozen_string_literal: true

# What an eaten meal actually took off the shelf, in the pantry
# ingredient's own unit. Stock is clamped at zero, so this is the real
# deduction — giving it back on undo is exact.
class MealConsumption < ApplicationRecord
  belongs_to :occurrence, inverse_of: :meal_consumptions
  belongs_to :ingredient

  validates :quantity, numericality: { greater_than: 0 }
  validates_accessible :ingredient, by: -> { occurrence&.event&.profile }
end
