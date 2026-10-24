# frozen_string_literal: true

module Assistant
  module Operations
    class Update < Base
      # A meal's recipes, written on the details row the change goes to. Only
      # saved recipes, so a meal never makes one up on the way.
      class MealRecipes < Part
        def initialize(record, add:, remove:, profile:)
          super(record, profile: profile)
          @adds = Array(add).map { |raw| recipe_name(raw) }.compact_blank
          @removals = Array(remove).map { |raw| recipe_name(raw) }.compact_blank
        end

        def any? = @adds.any? || @removals.any?

        # Added recipes must be ones the user can see (never created here);
        # dropped ones must be on the meal.
        def check
          accessible = Recipe.where(id: Recipe.accessible_by(profile).select(:id))
          @to_add = @adds.map { |name| [ name, NameMatch.find(accessible, name) ] }
          unknown = @to_add.reject(&:last).map(&:first)
          if unknown.any?
            known = accessible.order(:name).limit(15).pluck(:name)
            fail!("no recipe named #{unknown.map { |n| "\"#{n}\"" }.join(", ")}#{"; the user's recipes: #{known.join(", ")}" if known.any?}. " \
                  "A recipe must be saved (add_recipe) before a meal can use it")
          end
          on_meal = day_recipes
          @to_remove = @removals.map { |name| [ name, NameMatch.find(Recipe.where(id: on_meal.map(&:id)), name) ] }
          missing = @to_remove.reject(&:last).map(&:first)
          fail!("this meal doesn't have #{missing.map { |n| "\"#{n}\"" }.join(", ")}; it has: #{on_meal.map(&:name).join(", ").presence || "no recipes"}") if missing.any?
        end

        # Which details row holds the recipes this change writes, and what it
        # had: { "row" => "series" | "day", "ids" => [...] or nil (none of its own) }.
        def before
          if series_scope?
            { recipes_before: { "row" => "series", "ids" => record.event.details.meal_recipes.map(&:recipe_id) } }
          else
            own = record.own_details
            { recipes_before: { "row" => "day", "ids" => (own.meal_recipes.map(&:recipe_id).presence if own) } }
          end
        end

        def apply!(_applier)
          ids = day_recipes.map(&:id)
          ids -= @to_remove.filter_map(&:last).map(&:id)
          ids |= @to_add.filter_map(&:last).map(&:id)
          row = series_scope? ? record.event.details : (record.own_details || record.override_details.tap { |r| record.adopt_override_details!(r) })
          row.replace_recipes!(ids)
          Meal::Consumption.new(record).resync! if record.completed?
          []
        end

        private

        # A recipe the user named, from a plain string or { "name" => … }.
        def recipe_name(raw) = (raw.is_a?(Hash) ? raw["name"] || raw["recipe"] : raw).to_s.squish

        # The recipes the meal's day cooks: its own, else its series'.
        def day_recipes
          details = record.details
          lines = details.meal_recipes.reject(&:marked_for_destruction?)
          lines = details.series_row.meal_recipes.reject(&:marked_for_destruction?) if lines.empty? && !details.series?
          lines.map(&:recipe)
        end
      end
    end
  end
end
