# frozen_string_literal: true

# A spoken name resolved to the profile's ingredient or the household's
# unit, or to a new unsaved one written only when its owner is saved, so
# checking a draft never writes. Assistant::LabCatalog does the same for
# analytes, which also need aliases and a dictionary.
module Assistant
  class PantryCatalog
    def initialize(profile)
      @profile = profile
      @new_ingredients = {}
      @new_units = {}
    end

    # `strict`: only an exact or typo match counts (Assistant::NameMatch), for
    # writes that add stock; a looser name becomes a new ingredient.
    def ingredient(name, strict: false)
      name = name.to_s.squish
      return if name.empty?

      NameMatch.find(@profile.ingredients, name, strict: strict) ||
        @new_ingredients[name.downcase] ||= Ingredient.new(profile: @profile, name: name, quantity: 0)
    end

    def unit(name)
      name = name.to_s.squish
      return if name.empty?

      NameMatch.find(Unit.accessible_by(@profile), name) || @new_units[name.downcase] ||= Unit.new(name: name, household_id: @profile.household_id)
    end

    def new_ingredient_names = @new_ingredients.values.map(&:name)
  end
end
