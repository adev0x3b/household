# frozen_string_literal: true

module AssistantEval
  module Checks
    # What a scenario left in its throwaway profile, as the checks read it. A
    # kind of series is named as a scenario writes it: "lab_test_result".
    class Records
      attr_reader :profile

      def initialize(profile)
        @profile = profile
      end

      # The saved days of the profile's series of a kind.
      def days(type)
        Occurrence.of_type(kind(type)).where(event_id: series(type).select(:id))
      end

      def series(type) = Event.of_type(kind(type)).where(profile: profile)

      def lab_results = days("lab_test_result").order(:date, :id)
      def latest_lab = lab_results.last
      def appointments = days("appointment").includes(:event)
      def supply_purchases = SupplyPurchase.where(profile: profile).includes(:supply, :collection)
      def ingredients = Ingredient.where(profile: profile)
      def ingredient_purchases = IngredientPurchase.where(profile: profile).includes(:ingredient, :unit)
      def recipes = Recipe.where(profile: profile)
      def grocery_lists = GroceryList.where(profile: profile)

      private

      def kind(type)
        name = type.to_s.camelize
        Event::TYPES.include?(name) ? name : raise(KeyError, "no kind of series #{type}")
      end
    end
  end
end
