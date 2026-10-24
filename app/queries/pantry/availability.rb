# frozen_string_literal: true

# Compares what recipes need against a profile's own pantry. Ingredients are
# matched by name (case-insensitive), because a shared recipe's Ingredient
# rows belong to its owner while cooking draws from the cook's shelf.
#
#   Pantry::Availability.new(profile).for(recipes)      # one line per recipe ingredient
#   Pantry::Availability.new(profile).for_meal(recipes) # one need per pantry ingredient, summed
#
# Status: :ok (covered), :low (some but not enough), :out (none, or not in
# the pantry at all), :unknown (units that can't be converted — never warned).
module Pantry
  class Availability
    Line = Data.define(:recipe_ingredient, :ingredient, :needed, :on_hand, :unit, :status) do
      def shortfall = needed && on_hand ? [ needed - on_hand, 0 ].max : nil
      def short? = status == :low || status == :out
    end

    Need = Data.define(:ingredient, :needed, :on_hand, :unit, :status) do
      def short? = status == :low || status == :out
    end

    def initialize(profile)
      @profile = profile
    end

    def for(recipes)
      recipe_ingredients(recipes).map { |entry| line_for(entry) }
    end

    def for_meal(recipes)
      lines = self.for(recipes)
      pantry, missing = lines.partition(&:ingredient)

      needs = pantry.group_by(&:ingredient).map { |ingredient, group| combine(ingredient, group) }
      needs + missing.map { |line| Need.new(nil, line.needed, 0, line.unit, :out) }
    end

    def short?(recipes)
      self.for(recipes).any?(&:short?)
    end

    private

    def recipe_ingredients(recipes)
      Array(recipes).flat_map { |recipe| recipe.recipe_ingredients.to_a }
    end

    def line_for(entry)
      pantry = pantry_ingredient(entry.ingredient.name)
      return Line.new(entry, nil, entry.quantity, 0, entry.unit, :out) unless pantry

      needed = Unit.convert(entry.quantity, entry.unit, pantry.unit)
      return Line.new(entry, pantry, nil, pantry.quantity, pantry.unit, :unknown) if needed.nil?

      Line.new(entry, pantry, needed, pantry.quantity, pantry.unit, status_for(needed, pantry.quantity))
    end

    def combine(ingredient, lines)
      known = lines.reject { |line| line.status == :unknown }
      return Need.new(ingredient, nil, ingredient.quantity, ingredient.unit, :unknown) if known.empty?

      needed = known.sum(&:needed)
      Need.new(ingredient, needed, ingredient.quantity, ingredient.unit, status_for(needed, ingredient.quantity))
    end

    def status_for(needed, on_hand)
      return :ok if on_hand >= needed

      on_hand.positive? ? :low : :out
    end

    def pantry_ingredient(name)
      pantry_by_name[name.to_s.strip.downcase]
    end

    # The pantry as loaded for many meals' cards (Meal.preload_for_cards),
    # else read here.
    def pantry_by_name
      @pantry_by_name ||= begin
        ingredients = @profile.association(:ingredients).loaded? ? @profile.ingredients : @profile.ingredients.includes(:unit)
        ingredients.index_by { |ingredient| ingredient.name.strip.downcase }
      end
    end
  end
end
