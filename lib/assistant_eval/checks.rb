# frozen_string_literal: true

module AssistantEval
  # Every check a scenario's `expect` can name, one class each, in the order
  # the eval form offers them. A new check is a class here and a line in `all`.
  module Checks
    def self.all
      [ LabResults, LabValues, LabDate, LabStatus, Ranges, UndoneChanges, Purchases, PurchaseDetails, TherapyLinks, MedicationDetails,
        Appointments, OneAppointment, RecordStatus, Times, Statuses, Repeats, Series, SharedWith, Stock, Supplies, Untouched,
        MemberPayment, Analytes, Ingredients, IngredientDetails, IngredientPurchases, IngredientPurchaseDetails, Recipes,
        RecipeDetails, Meals, MealDetails, GroceryLists, GroceryListItems, PendingDeletions,
        Asks, Saves, HonestReplies, ReplyLanguage, ReplyExcludes, Budget, PlainReplies ]
    end

    # nil for a name no check has.
    def self.named(name) = all.find { _1.key == name.to_s }
  end
end
