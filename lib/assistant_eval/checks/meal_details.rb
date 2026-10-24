# frozen_string_literal: true

module AssistantEval
  module Checks
    # Several meals can share a day (lunch and dinner), so the one closest to
    # what is expected is judged.
    class MealDetails < Base
      def self.key = "meal_details"
      def self.argument = "A meal (or a list of them): date, plus any of name / meal_type / kind / status / recipes / cost / paid / category"
      def self.example = { "date" => "2026-10-02", "meal_type" => "dinner", "recipes" => [ "Pancakes" ], "status" => "pending" }

      def call(expected)
        wrong = Array.wrap(expected).filter_map do |want|
          date = Date.parse(want["date"].to_s)
          candidates = records.days("meal").where(date: date).to_a.select { |m| named?(m, want["name"]) }
          next "no meal on #{date}" if candidates.empty?

          problems = candidates.map { |meal| problems_of(meal, want) }.min_by(&:size)
          "#{date}: #{problems.join(", ")}" if problems.any?
        end
        "meal_details: #{wrong.join("; ")}" if wrong.any?
      end

      private

      def problems_of(meal, want)
        cost = meal.costs.first
        details = meal.details
        recipes = Assistant::Resources.meal_recipe_names(meal)
        problems = []
        problems << "meal_type #{details.meal_type}" if want["meal_type"] && details.meal_type != want["meal_type"].to_s
        problems << "kind #{details.kind}" if want["kind"] && details.kind != want["kind"].to_s
        problems << "status #{meal.status}" if want["status"] && meal.status != want["status"].to_s
        problems << "recipes #{recipes.sort}" if want["recipes"] && recipes.map(&:downcase).sort != Array(want["recipes"]).map { |n| n.to_s.downcase }.sort
        problems << "cost #{amount(cost).to_f}" if want["cost"] && !same_number?(amount(cost), want["cost"])
        problems << "paid #{paid_with(cost)}" if want["paid"] && paid_with(cost) != want["paid"].to_s
        problems << "category #{category_of(cost)}" if want["category"] && category_of(cost) != want["category"].to_s
        problems
      end
    end
  end
end
