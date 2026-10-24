# frozen_string_literal: true

class Meal
  class Details < ::Details::Base
    self.table_name = "meal_details"

    enum :kind, { home: 0, eating_out: 1, ordered_in: 2 }
    enum :meal_type, { breakfast: 0, lunch: 1, dinner: 2, snack: 3 }

    has_many :meal_recipes, foreign_key: :meal_details_id, dependent: :destroy, inverse_of: :meal_details
    has_many :recipes, through: :meal_recipes
    accepts_nested_attributes_for :meal_recipes, allow_destroy: true,
                                                 reject_if: ->(attrs) { attrs["recipe_id"].blank? }
    reads_access_of :meal_recipes

    def self.recorded = %i[kind meal_type]

    # A meal is read with its recipes and what they need (the card's pantry check).
    def self.preloads = [ :meal_recipes, { recipes: { recipe_ingredients: %i[ingredient unit] } } ]
    def self.label_preloads = [ :recipes ]
    def self.lists = %i[meal_recipes]

    inherits :kind, :meal_type
    series_requires :kind

    after_initialize { self.kind ||= :home if series? && new_record? }

    def home? = kind.to_s == "home"

    # Its recipes made exactly `ids` (none, on a day's own row: the day
    # reads its series' again). The assistant's recipe changes and their
    # undo; a form saves the list through nested attributes.
    def replace_recipes!(ids)
      ids = Array(ids).map(&:to_i)
      transaction do
        meal_recipes.where.not(recipe_id: ids).destroy_all
        added = (ids - meal_recipes.pluck(:recipe_id)).map { |id| meal_recipes.build(recipe_id: id) }
        MealRecipe.read_access(added)
        added.each(&:save!)
      end
      meal_recipes.reset
    end

    # The recipes as a day reads them: its own when it has any, else the series'.
    def resolved_recipes
      return recipes if series? || meal_recipes.reject(&:marked_for_destruction?).any?

      series_row.recipes
    end
  end
end
