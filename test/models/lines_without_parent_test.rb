# frozen_string_literal: true

require "test_helper"

# A line built without its parent — a value without its report, a use
# without its dose — is refused for that. What it points at has no owner to
# be checked against yet, and checking never raises.
class LinesWithoutParentTest < ActiveSupport::TestCase
  test "each kind of line is refused for its missing parent, and only for that" do
    alice = profiles(:alice)
    supply = supply_purchase!(profile: alice, name: "Needles").supply
    lines = [
      [ RecipeIngredient.new(ingredient: ingredients(:flour), unit: units(:kg), quantity: 1), :recipe ],
      [ LabTestResultEntry.new(analyte: analytes(:glucose), unit: units(:mgdl), value: "90"), :occurrence ],
      [ MealConsumption.new(ingredient: ingredients(:flour), quantity: 1), :occurrence ],
      [ SupplyConsumption.new(supply: supply, quantity: 1), :occurrence ],
      [ SupplyUse.new(supply: supply, quantity: 1), :medication_details ],
      [ MealRecipe.new(recipe: recipes(:roast_chicken)), :meal_details ],
      [ GroceryListItem.new(ingredient: ingredients(:flour), unit: units(:kg), quantity: 1), :grocery_list ],
      [ ReferenceRange.new(unit: units(:mgdl), low: 1, high: 2), :analyte ],
      [ EventShare.new(profile: profiles(:bob)), :event ]
    ]

    lines.each do |line, parent|
      assert_not line.valid?, line.class.name
      assert_equal [ parent ], line.errors.attribute_names, "#{line.class.name}: #{line.errors.full_messages.to_sentence}"
    end
  end
end
