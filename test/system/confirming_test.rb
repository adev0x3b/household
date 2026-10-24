# frozen_string_literal: true

require "application_system_test_case"

# A press that asks first asks in the app's own dialog
# (confirm_dialog_controller.js), never the browser's confirm(): the
# question in the reader's language, and a button named after the press.
class ConfirmingTest < ApplicationSystemTestCase
  test "deleting asks first, keeps the recipe on Cancel, and deletes it on yes" do
    recipe = profiles(:alice).recipes.create!(name: "Lentil soup")
    sign_in profiles(:alice)
    visit recipes_path

    press_delete(recipe)
    within("dialog#confirm_dialog[open]") do
      assert_text I18n.t("recipes.confirm_destroy", name: recipe.name)
      assert_selector "button.modal__btn--danger", text: I18n.t("recipes.card.destroy")
      click_on I18n.t("confirm_dialog.cancel")
    end
    assert_no_selector "dialog#confirm_dialog[open]"
    assert_selector "#recipe_#{recipe.id}"

    press_delete(recipe)
    within("dialog#confirm_dialog[open]") { click_on I18n.t("recipes.card.destroy") }
    assert_no_selector "#recipe_#{recipe.id}"
    assert_not Recipe.exists?(recipe.id)
  end

  private

  def press_delete(recipe)
    within("#recipe_#{recipe.id}") do
      click_on I18n.t("recipes.card.more")
      click_on I18n.t("recipes.card.destroy")
    end
  end
end
