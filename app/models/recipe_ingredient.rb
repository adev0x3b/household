# frozen_string_literal: true

class RecipeIngredient < ApplicationRecord
  belongs_to :recipe
  belongs_to :ingredient
  belongs_to :unit, optional: true

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :ingredient_id, uniqueness: { scope: :recipe_id }
  validates_accessible :ingredient, by: -> { recipe&.profile }
  validates_within_household :unit, of: -> { recipe&.profile }

  # Typed by name into the recipe owner's catalog, not the editor's: a
  # housemate the recipe is shared with typing a new ingredient adds it to
  # the owner's.
  def ingredient_name=(name)
    type_name(:ingredient, name) { { profile_id: recipe.profile_id } }
  end

  def unit_name=(name)
    type_name(:unit, name) { { household_id: recipe.profile.household_id } }
  end
end
