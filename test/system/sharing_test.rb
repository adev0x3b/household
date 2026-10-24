# frozen_string_literal: true

require "application_system_test_case"

# Sharing is one modal for every kind of thing: a housemate picked from the
# household, who then finds the thing among their own.
class SharingTest < ApplicationSystemTestCase
  test "a recipe shared with a housemate is on the housemate's list, and opens for them" do
    alice, carol = profiles(:alice), profiles(:carol)
    recipe = alice.recipes.create!(name: "Lentil soup")

    sign_in alice
    visit recipes_path
    within("#recipe_#{recipe.id}") do
      click_on I18n.t("recipes.card.more")
      click_on I18n.t("recipes.card.share")
    end
    within(".modal") do
      assert_no_select I18n.t("shares.with_label"), with_options: [ profiles(:outsider).display_name ] # never outside the household
      select carol.display_name, from: I18n.t("shares.with_label")
      click_on I18n.t("shares.share")
      assert_text carol.display_name # among the people with access
      assert_accessible "a recipe's sharing, with a housemate added"
    end
    assert_text I18n.t("shares.notices.shared", name: carol.display_name)

    using_session(:carol) do
      sign_in carol
      visit recipes_path
      click_on "Lentil soup"
      assert_selector "h1", text: "Lentil soup"
    end
  end
end
