# frozen_string_literal: true

class Meal
  # What a home meal does to the pantry: eaten, each recipe ingredient the
  # cook has leaves the shelf (converted to the pantry's unit, clamped at
  # zero), recorded on the day as a MealConsumption so an undo gives back
  # exactly what was taken.
  class Consumption
    def initialize(occurrence)
      @occurrence = occurrence
    end

    # The ingredients are locked together, in one order, so two meals eaten
    # at once wait for each other instead of each taking what the other
    # read; what they took is checked together, then saved.
    def record!
      return unless @occurrence.details.home?
      return if @occurrence.meal_consumptions.exists?

      recipes = @occurrence.details.resolved_recipes.includes(recipe_ingredients: %i[ingredient unit])
      needs = Pantry::Availability.new(@occurrence.profile).for_meal(recipes).select { |need| need.ingredient && need.needed }
      Ingredient.transaction do
        shelf = Ingredient.where(id: needs.map { _1.ingredient.id }).order(:id).lock.index_by(&:id)
        taken = needs.filter_map do |need|
          ingredient = shelf.fetch(need.ingredient.id)
          deducted = [ need.needed, ingredient.quantity ].min
          next unless deducted.positive?

          ingredient.adjust_stock!(-deducted)
          @occurrence.meal_consumptions.build(ingredient: ingredient, quantity: deducted)
        end
        MealConsumption.read_access(taken)
        taken.each(&:save!)
      end
    end

    def reverse! = self.class.reverse_all!([ @occurrence ])

    # What many meals took goes back on the shelf, an ingredient at a time
    # (deleting a series' days at once).
    def self.reverse_all!(days)
      days = days.select(&:persisted?)
      consumptions = MealConsumption.where(occurrence_id: days.map(&:id)).includes(:ingredient).to_a
      consumptions.group_by(&:ingredient).each { |ingredient, taken| ingredient.adjust_stock!(taken.sum(&:quantity)) }
      MealConsumption.where(id: consumptions.map(&:id)).delete_all
      days.each { |day| day.meal_consumptions.reset }
    end

    # After the recipes of an eaten meal changed.
    def resync!
      reverse!
      record!
    end
  end
end
