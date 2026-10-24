# frozen_string_literal: true

module Assistant
  # Only saves the meals: a cooked meal's ingredients leave the pantry when
  # it is marked done.
  class PlanMealsTool < ChangeTool
    KINDS = Meal::Details.kinds.keys.freeze
    MEAL_TYPES = Meal::Details.meal_types.keys.freeze

    description "Saves meals — also for \"let's make / have pasta for lunch and X for dinner\" — one entry per meal, all in one call, also to plan several days (a week of dinners). " \
                "A meal at home lists recipes by name: only recipes the user already has (search_records type recipe first). " \
                "A meal out or ordered in has no recipes: give kind, a title (the place) and, if said, amount and payment_method. " \
                "Past meals are saved as eaten, future ones as planned. To change or mark a saved meal use update_record / mark_done."
    parameters(
      type: "object",
      properties: {
        meals: {
          type: "array",
          items: {
            type: "object",
            properties: {
              date: DATE,
              meal_type: { type: "string", enum: MEAL_TYPES },
              kind: { type: "string", enum: KINDS, description: "home (cooked), eating_out or ordered_in. Default home" },
              recipes: { type: "array", items: { type: "string" }, description: "Names of saved recipes cooked in this meal" },
              title: { type: "string", description: "Only for a meal out or ordered in: the place. Never the name of a dish cooked at home (that goes in recipes)" },
              amount: { type: "number", description: "What a meal out or ordered in cost" },
              payment_method: PAYMENT,
              notes: { type: "string" }
            },
            required: %w[date]
          }
        },
        **RECURRENCE, confirm: CONFIRM
      },
      required: %w[meals]
    )

    def execute(meals: [], repeat: nil, every: nil, days: nil, ends: nil, confirm: false)
      fail!("meals is empty") if Array(meals).empty?

      repeats = recurrence(repeat, every, days, ends)
      ops = Array(meals).map do |meal|
        meal = recipe_from_title(meal.to_h.stringify_keys)
        fields = { date: meal["date"], meal_type: meal["meal_type"], kind: meal["kind"], title: meal["title"], notes: meal["notes"],
                   recipes: Array(meal["recipes"]).map(&:to_s), amount: meal["amount"], payment_method: meal["payment_method"],
                   recurrence: repeats }
        { op: "create", type: "meal", fields: fields }
      end
      submit(ops, confirm: confirm)
    end

    private

    # Small models put the dish in the title, so a home meal with no recipes
    # whose title is a saved recipe is that recipe.
    def recipe_from_title(meal)
      return meal if Array(meal["recipes"]).any? || meal["title"].blank? || %w[eating_out ordered_in].include?(meal["kind"].to_s)

      recipe = NameMatch.find(Recipe.where(id: Recipe.accessible_by(profile).select(:id)), meal["title"].to_s.squish)
      recipe ? meal.merge("recipes" => [ recipe.name ], "title" => nil) : meal
    end
  end
end
