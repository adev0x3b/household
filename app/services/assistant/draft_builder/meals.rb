# frozen_string_literal: true

module Assistant
  class DraftBuilder
    # A meal: cooked at home from the user's saved recipes, or eaten out or
    # ordered in, with what it cost. A home meal has no price of its own,
    # since what it cooks was paid for when the groceries were bought.
    class Meals < Series
      def meal_recipes = recipe_lookups.filter_map(&:last).uniq

      # A meal never has a price when it is cooked at home: one sent with it
      # is ignored, not asked about.
      def cost_requested? = !series.details.home? && super

      # A recipe the user named that isn't theirs is never created from a
      # meal: the model gets the names that exist, to pick one or ask.
      def unresolved
        names = recipe_lookups.reject(&:last).map(&:first)
        return [] if names.empty?

        known = accessible_recipes.order(:name).limit(15).pluck(:name)
        [ { "field" => "meal.recipes",
            "problem" => "no recipe named #{names.map { |n| "\"#{n}\"" }.join(", ")}#{"; the user's recipes: #{known.join(", ")}" if known.any?}. " \
                         "Use one of those names, or ask the user — a recipe must be saved (add_recipe) before a meal can use it" } ]
      end

      # A price a home meal can't take, and what the pantry can't cover for
      # its recipes (the meal is saved all the same).
      def notes
        return [] unless series.details.home?

        notes = []
        notes << "price not saved: a home meal has no price of its own" if cost_given?
        short = Resources.pantry_shortages(meal_recipes.select(&:persisted?), profile).values.flatten.uniq
        notes << "the pantry is short for #{short.join("; ")} — tell the user" if short.any?
        notes
      end

      # "Dinner: Pancakes, Roast chicken" or "Dinner: Trattoria Roma", the
      # part of the day first.
      def label
        details = series.details
        names = details.home? ? Resources.meal_recipe_names(record).to_sentence.presence : nil
        what = names || series.title.presence || type_label
        with_date(details.meal_type ? "#{I18n.t("meals.meal_type.#{details.meal_type}")}: #{what}" : what, record.date)
      end

      private

      def cost_section = :optional

      def normalize(field, value)
        case field
        when "kind" then Normalize.meal_kind(value)
        when "meal_type" then Normalize.meal_type(value)
        else super
        end
      end

      # No kind said: a price and no recipe is a meal out, anything else is
      # cooked at home.
      def fill_in(event, given)
        details = event.details
        details.kind = cost_given? && meal_recipes.empty? ? "eating_out" : "home" unless given.key?("kind")
        meal_recipes.each { |recipe| details.meal_recipes.build(recipe: recipe) }
      end

      def duplicate_query = record.title.presence || Resources.meal_recipe_names(record).first

      # A meal out is paid with the meal: still unpaid while it is only planned.
      def attach_fee(committer, day)
        committer.attach_cost(day, date: day.date, title: series.cost_title(day), counterparty: series.cost_counterpart(day),
                                   status: done?(day) ? :completed : :pending, category: series.fee_category)
      end

      def accessible_recipes = Recipe.where(id: Recipe.accessible_by(profile).select(:id))

      # The recipes it names that the profile can see (own or shared), by the
      # same name matching as every other catalog.
      def recipe_lookups
        @recipe_lookups ||= Array(draft.payload["recipes"]).filter_map do |item|
          name = item.to_s.squish
          [ name, NameMatch.find(accessible_recipes, name) ] if name.present?
        end
      end
    end
  end
end
