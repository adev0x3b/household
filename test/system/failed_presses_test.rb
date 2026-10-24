# frozen_string_literal: true

require "application_system_test_case"

# A press whose request fails is told where the person stands, and the page,
# the open modal and what was typed stay as they were
# (failed_request_controller.js, ApplicationController#answer_in_place).
class FailedPressesTest < ApplicationSystemTestCase
  setup do
    @recipe = recipes(:roast_chicken)
    sign_in profiles(:alice)
    visit recipes_path
  end

  test "a save that meets a crash keeps the modal and what was typed" do
    open_edit_modal
    fill_in I18n.t("recipes.form.name_label"), with: "Roast chicken with lemon"

    StandInAnswers.answering(recipe_path(@recipe), status: 500) do
      click_on I18n.t("recipes.form.update")

      assert_alert_toast I18n.t("failures.server_error")
    end
    assert_field I18n.t("recipes.form.name_label"), with: "Roast chicken with lemon"
    assert_no_selector "html[aria-busy]"
    assert_equal "Sunday Roast Chicken", @recipe.reload.name
  end

  test "a link to another page that meets a crash stays on the page it was pressed on" do
    StandInAnswers.answering(recipe_path(@recipe), status: 500) do
      click_on @recipe.name

      assert_alert_toast I18n.t("failures.server_error")
    end
    assert_current_path recipes_path
    assert_selector "#recipe_#{@recipe.id}"
    assert_no_selector "html[aria-busy]"
  end

  test "Back to a page that crashes shows the error page whole, since the address has already changed" do
    click_on @recipe.name
    assert_current_path recipe_path(@recipe)

    StandInAnswers.answering(recipes_path, status: 500) do
      go_back

      assert_selector "h1", text: I18n.t("public_pages.pages.server_error.title")
    end
    # Loaded as a page of its own, with its styles, rather than drawn by
    # Turbo into the app's page, whose policy refuses them.
    assert_nil evaluate_script("window.Turbo")
  end

  test "a press with no connection says so, and the page stays" do
    open_edit_modal
    fill_in I18n.t("recipes.form.name_label"), with: "Roast chicken with lemon"

    offline do
      click_on I18n.t("recipes.form.update")

      assert_alert_toast I18n.t("failures.offline")
    end
    assert_field I18n.t("recipes.form.name_label"), with: "Roast chicken with lemon"
    assert_button I18n.t("recipes.form.update"), disabled: false
  end

  test "the bell opened offline says so, and loads its list when opened again online" do
    offline do
      click_on I18n.t("notifications.title")

      assert_alert_toast I18n.t("failures.offline")
      assert_selector ".notifications__loading"
      click_on I18n.t("notifications.title")
    end

    click_on I18n.t("notifications.title")
    within(".notifications__panel") { assert_no_selector ".notifications__loading" }
  end

  test "a search whose answer doesn't hold the results keeps the results it had" do
    StandInAnswers.answering(recipes_path, status: 404) do
      find("input[name=q]").set("chicken")

      assert_alert_toast I18n.t("failures.missing")
    end
    assert_selector "#recipe_#{@recipe.id}"
    assert_no_text "Content missing"
  end

  test "editing what a housemate has just deleted says it is gone, and takes it off the page" do
    @recipe.destroy!

    within("#recipe_#{@recipe.id}") { click_on I18n.t("recipes.card.edit") }

    assert_alert_toast I18n.t("failures.gone")
    assert_no_selector "#recipe_#{@recipe.id}"
    assert_current_path recipes_path
  end

  private

  def open_edit_modal
    within("#recipe_#{@recipe.id}") { click_on I18n.t("recipes.card.edit") }
    assert_selector ".modal", text: I18n.t("recipes.form.edit_title")
  end

  # On the page, or inside the modal while one is open, the only place a
  # toast can then be seen and pressed.
  def assert_alert_toast(message)
    assert_selector ".toast-container .toast--alert", text: message
  end

  # The browser's own switch, as a phone that has lost its signal: Turbo's
  # requests fail before they leave it.
  def offline
    page.driver.browser.network_conditions = { offline: true, latency: 0, throughput: 0 }
    yield
  ensure
    page.driver.browser.network_conditions = { offline: false, latency: 0, throughput: -1 }
  end
end
