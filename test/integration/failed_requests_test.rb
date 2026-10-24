# frozen_string_literal: true

require "test_helper"

# What a request the app can't carry out answers, where the person stands:
# the thing was deleted a moment ago, or the form's token no longer matches
# the session. A page opened directly, with nowhere to stay, gets the
# public page for the status instead.
class FailedRequestsTest < ActionDispatch::IntegrationTest
  setup do
    @recipe = recipes(:roast_chicken)
    sign_in profiles(:alice)
  end

  test "a modal asked for a deleted record answers a toast and 404, and brings the page up to date" do
    get edit_recipe_path(@recipe.id + 1000), as: :turbo_stream

    assert_response :not_found
    assert_toast I18n.t("failures.gone")
    assert_page_refreshed
  end

  test "a page Turbo visits for a deleted record goes back to the page it came from, with the toast" do
    get recipe_path(@recipe.id + 1000), headers: visited_from(recipes_path)

    assert_redirected_to recipes_path
    follow_redirect!
    assert_toast I18n.t("failures.gone")
  end

  test "a deleted record's own page, refreshed, leads home rather than back to itself" do
    gone = recipe_path(@recipe.id + 1000)
    get gone, headers: visited_from(gone)

    assert_redirected_to root_path
  end

  test "a deleted record's page opened directly is the public 404 page" do
    get recipe_path(@recipe.id + 1000)

    assert_response :not_found
    assert_select ".toast", count: 0
  end

  test "JSON is told the reason with the status" do
    get recipe_path(@recipe.id + 1000), as: :json

    assert_response :not_found
    assert_equal I18n.t("failures.gone"), response.parsed_body["error"]
  end

  test "a form whose token no longer matches the session answers a toast and 422, and changes nothing" do
    protecting_forms do
      assert_no_difference -> { Recipe.count } do
        delete recipe_path(@recipe), headers: submitted_from(recipe_path(@recipe))
      end
    end

    assert_response :unprocessable_content
    assert_toast I18n.t("failures.page_out_of_date")
    assert_page_refreshed
  end

  test "a write that meets a newer copy of its record answers a toast and 409, and brings the page up to date" do
    item = grocery_list_items(:flour_item)
    swapping(GroceryLists::Broadcaster, :changed, ->(_list) { raise ActiveRecord::StaleObjectError.new(item, "update") }) do
      post grocery_list_item_check_path(item), as: :turbo_stream
    end

    assert_response :conflict
    assert_toast I18n.t("failures.changed_meanwhile")
    assert_page_refreshed
  end

  test "a form posted outside Turbo with a stale token gets the public 422 page" do
    protecting_forms { delete recipe_path(@recipe) }

    assert_response :unprocessable_content
    assert_select ".toast", count: 0
    assert_predicate Recipe.where(id: @recipe.id), :exists?
  end

  private

  # A refresh named after the request is taken by the page for an echo of
  # its own change, and left out.
  def assert_page_refreshed
    assert_select "turbo-stream[action=refresh]:not([request-id])", 1
  end

  # A page Turbo asked for, as a link in the app does: Turbo names each of
  # its requests, and the browser says which page the link was on.
  def visited_from(path)
    { "Accept" => "text/html, application/xhtml+xml", "X-Turbo-Request-Id" => SecureRandom.uuid,
      "Referer" => "http://www.example.com#{path}" }
  end

  # Request tests skip the token check, so a stale token is only seen with it on.
  def protecting_forms
    protecting = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = protecting
  end
end
