# frozen_string_literal: true

require "test_helper"

class IngredientsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @profile = profiles(:alice)
    sign_in @profile
  end

  test "index lists only the profile's ingredients, with quantities localized" do
    get ingredients_path

    assert_response :success
    assert_includes response.body, "Flour"
    assert_includes response.body, "2.5 kg"
    assert_includes response.body, "12 pcs"
    assert_not_includes response.body, "12.0 pcs"
    assert_not_includes response.body, "Olive oil"
  end

  test "create adds an ingredient to the profile, from the form in a modal, and comes back to the pantry as it was" do
    get new_ingredient_path, as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals] form[action=?] input[name='ingredient[name]']", ingredients_path

    searched = ingredients_path(q: "butter")
    assert_difference -> { @profile.ingredients.count }, 1 do
      post ingredients_path, params: { ingredient: { name: "Butter", quantity: "2", unit_name: "pcs" } }, headers: submitted_from(searched)
    end
    assert_redirected_to searched
    follow_redirect!
    assert_select ".ingredient-card__name", text: "Butter"
  end

  test "an ingredient the pantry has already, in any case, stays on the form" do
    assert_no_difference -> { Ingredient.count } do
      post ingredients_path, as: :turbo_stream, params: { ingredient: { name: "flour", quantity: "1", unit_name: "kg" } }
    end
    assert_response :unprocessable_content
    assert_form_error "Name has already been taken"
  end

  test "history is a page, searched from the top bar, each purchase changed on its row" do
    flour = ingredients(:flour)
    purchase = flour.ingredient_purchases.create!(profile: @profile, quantity: 1, purchased_on: Date.new(2026, 10, 1))

    get ingredient_purchases_path(flour)

    assert_response :success
    assert_select "h1.page-title", I18n.t("ingredients.history.title", name: flour.name)
    assert_select "a.ingredient-history__back[href=?]", ingredients_path
    assert_select ".navbar-topbar-controls form[action=?] input[name=q]", ingredient_purchases_path(flour)
    assert_select ".navbar-topbar-controls a[href=?][data-turbo-stream]", new_ingredient_purchase_path(flour)
    assert_select "turbo-frame#ingredient_history_results .ingredient-purchase-row", text: /1 kg/
    assert_select "a.item-action[href=?][data-turbo-stream]", edit_ingredient_purchase_path(purchase)
    assert_select "a.item-action--danger[href=?][data-turbo-method=delete][data-turbo-confirm]", ingredient_purchase_path(purchase)
  end

  test "history narrows by search through the frame" do
    flour = ingredients(:flour)
    flour.ingredient_purchases.create!(profile: @profile, quantity: 1, purchased_on: Date.new(2026, 10, 1))
    flour.ingredient_purchases.create!(profile: @profile, quantity: 7, purchased_on: Date.new(2026, 9, 3))

    get ingredient_purchases_path(flour, q: "2026-09"), headers: { "Turbo-Frame" => Views::IngredientPurchases::List::FRAME_ID }

    assert_response :success
    assert_includes response.body, "7 kg"
    assert_not_includes response.body, "1 kg<"
    # Only the results frame comes back — never the search input being typed into.
    assert_includes response.body, %(id="#{Views::IngredientPurchases::List::FRAME_ID}")
    assert_not_includes response.body, 'type="search"'
  end

  test "history of someone else's ingredient is not found" do
    get ingredient_purchases_path(ingredients(:olive_oil))
    assert_response :not_found
  end

  test "destroy removes an unused ingredient and its purchases" do
    butter = Ingredient.create!(profile: @profile, name: "Butter", unit_name: "pcs")
    butter.ingredient_purchases.create!(profile: @profile, quantity: 1, purchased_on: Date.current)

    assert_difference -> { Ingredient.count }, -1 do
      delete ingredient_path(butter), headers: submitted_from(ingredients_path)
    end
    assert_redirected_to ingredients_path
  end

  test "destroy of an ingredient a grocery list uses tells the user instead of failing" do
    flour = ingredients(:flour) # on a grocery list via fixtures

    assert_no_difference -> { Ingredient.count } do
      delete ingredient_path(flour), as: :turbo_stream
    end

    assert_response :unprocessable_content
    assert_toast "can't be deleted"
  end

  test "index localizes quantities in Italian" do
    ingredients(:flour).update!(quantity: 2.5)

    get ingredients_path, headers: { "Accept-Language" => "it" }

    assert_response :success
    assert_includes response.body, "2,5 kg"
  ensure
    I18n.locale = I18n.default_locale
  end
end

class IngredientsCategoryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @profile = profiles(:alice)
    sign_in @profile
  end

  test "an ingredient is created in its store section and the card shows it" do
    post ingredients_path, params: { ingredient: { name: "Apples", quantity: "4", unit_name: "pcs", category: "produce" } }, headers: submitted_from(ingredients_path)

    assert_predicate @profile.ingredients.find_by(name: "Apples"), :produce?
    follow_redirect!
    assert_includes response.body, 'title="Produce"'
  end

  test "the form offers the store sections" do
    get edit_ingredient_path(ingredients(:flour)), as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'name="ingredient[category]"'
    assert_includes response.body, "Dairy &amp; eggs"
  end
end
