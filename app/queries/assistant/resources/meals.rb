# frozen_string_literal: true

module Assistant
  module Resources
    class Meals < CalendarResource
      def key = "meal"
      def type = Meal
      def recipes? = true
      def search_columns = %i[title notes]
      def writable = %w[kind meal_type title notes date]
      def enums = { "kind" => Meal::Details.kinds.keys, "meal_type" => Meal::Details.meal_types.keys }

      # A meal is also found by the recipes it cooks: its own day's, or its
      # series' for the days that follow it.
      def search_also(matching)
        own = MealRecipe.joins(:recipe, :meal_details).where(matching.call(%w[recipes.name])).where.not(meal_details: { occurrence_id: nil })
        series = MealRecipe.joins(:recipe, :meal_details).where(matching.call(%w[recipes.name])).where(meal_details: { occurrence_id: nil })
        Occurrence.where(id: own.select("meal_details.occurrence_id")).or(Occurrence.where(event_id: series.select("meal_details.event_id"))).select(:id)
      end

      # A meal's recipes come with its details (Meal::Details.preloads).
      def summaries(meals, _profile)
        meals.map do |meal|
          { title: meal.title, kind: meal.details.kind, meal_type: meal.details.meal_type, recipes: meal_recipe_names(meal).presence }
            .merge(cost_fields(meal))
        end
      end

      private

      def projected_text(day) = TextMatch.fold("#{super} #{meal_recipe_names(day).join(" ")}")
    end
  end
end
