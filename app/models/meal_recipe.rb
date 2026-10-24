# frozen_string_literal: true

# A recipe a meal is cooked from: on the series' details (every day) or on
# one day's override (that day alone).
class MealRecipe < ApplicationRecord
  include Details::ListItem

  belongs_to :meal_details, class_name: "Meal::Details", inverse_of: :meal_recipes
  belongs_to :recipe

  list_of :meal_details, as: :meal_recipes

  validates :recipe_id, uniqueness: { scope: :meal_details_id }
  # Never the picker's raw id: a meal only holds recipes its owner can see
  # (their own, or shared with them).
  validates_accessible :recipe, by: -> { meal_details&.event&.profile }
end
