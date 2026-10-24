# frozen_string_literal: true

module MealBuilders
  def pantry_ingredient(profile, name, quantity:, unit: "kg")
    Ingredient.create!(profile: profile, name: name, quantity: quantity, unit: Unit.find_or_create_by_name(unit, household_id: profile.household_id))
  end

  # A recipe whose ingredients are [ name, quantity, unit ] triples. Ingredients
  # not already on the owner's shelf are created there with no stock.
  def recipe_with(profile, name, *lines)
    recipe = Recipe.create!(profile: profile, name: name)
    lines.each do |ingredient_name, quantity, unit|
      ingredient = Ingredient.find_or_create_by_name(ingredient_name, profile_id: profile.id)
      recipe.recipe_ingredients.create!(ingredient: ingredient, quantity: quantity, unit: Unit.find_or_create_by_name(unit, household_id: profile.household_id))
    end
    recipe
  end

  # A one-off meal on `date` (its series and its stored day); returns the day.
  # `status` is set as stored, without what completing does (no pantry draw).
  def meal_on(profile, date, recipes: [], title: nil, kind: :home, meal_type: nil, rrule: nil, status: nil)
    meal = Meal.new(profile: profile, starts_on: date, title: title, rrule: rrule)
    meal.details.assign_attributes(kind: kind, meal_type: meal_type)
    recipes.each { |recipe| meal.details.meal_recipes.build(recipe: recipe) }
    meal.save!
    return meal.occurrence_on(date).materialize! unless status

    day!(meal, date: date, status: status)
  end
end
