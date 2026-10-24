# frozen_string_literal: true

require "application_system_test_case"

# A meal cooked at home from a recipe: the form shows the recipes for a
# home meal and the cost for one eaten out (meal_form_controller.js), and
# a meal marked eaten takes its recipe's ingredients out of the pantry.
class MealsTest < ApplicationSystemTestCase
  test "a dinner cooked from a recipe and eaten takes the recipe's ingredients from the pantry" do
    recipe, flour = recipes(:roast_chicken), ingredients(:flour) # half a kilo of the pantry's 2.5 kg
    sign_in profiles(:alice)
    visit calendar_path

    add_to_day(Date.current, :meal)
    within(".modal") do
      select I18n.t("meals.kind.eating_out"), from: I18n.t("meals.form.kind_label")
      assert_no_button I18n.t("meals.form.recipes.add")
      assert_text I18n.t("meals.form.cost_section.label")
      select I18n.t("meals.kind.home"), from: I18n.t("meals.form.kind_label")
      assert_no_text I18n.t("meals.form.cost_section.label")

      select I18n.t("meals.meal_type.dinner"), from: I18n.t("meals.form.meal_type_label")
      click_on I18n.t("meals.form.recipes.add")
      select recipe.name, from: I18n.t("meals.form.recipes.placeholder")
      assert_accessible "a new home meal's form, with a recipe"
      click_on I18n.t("meals.form.create")
    end
    assert_text I18n.t("meals.notices.created")

    within_day(Date.current) { click_on I18n.t("calendar.day_card.complete", title: recipe.name) } # named after its recipe
    assert_text I18n.t("meals.notices.completed")
    assert_equal 2, flour.reload.quantity

    visit ingredients_path
    within("#ingredient_#{flour.id}") { assert_text "2 kg" }
  end
end
