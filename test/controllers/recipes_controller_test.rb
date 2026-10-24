# frozen_string_literal: true

require "test_helper"

class RecipesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @cook = profiles(:alice)
    sign_in @cook
  end

  test "show warns under the ingredients when the pantry is short" do
    recipe = recipe_with(@cook, "Big bread", [ "Flour", 3, "kg" ])
    get recipe_path(recipe)

    assert_response :success
    assert_select ".recipe-pantry-warning li", text: /Flour: you have 2.5 kg, you need 3 kg/
    assert_select ".recipe-ingredients__item--low", count: 1
  end

  test "show has no warning when the pantry covers the recipe" do
    recipe = recipe_with(@cook, "Bread", [ "Flour", 500, "g" ])
    get recipe_path(recipe)

    assert_response :success
    assert_select ".recipe-pantry-warning", count: 0
  end

  test "a shared recipe is judged against the viewer's pantry" do
    sign_in profiles(:bob)
    get recipe_path(recipes(:roast_chicken))

    assert_response :success
    assert_select ".recipe-pantry-warning li", text: /Flour: not in your pantry/
    assert_not_includes response.body, "2.5"
  end

  test "a new recipe starts with a step and an ingredient; a typed ingredient joins the pantry" do
    get new_recipe_path, as: :turbo_stream
    assert_select "turbo-stream[action=update][target=modals] form[action=?]", recipes_path do
      assert_select ".recipe-step-row textarea[name$='[instruction]']"
      assert_select "input[name$='[ingredient_name]'][list=ingredients-datalist]"
    end
    assert_select "datalist#ingredients-datalist option[value=Flour]"

    assert_difference -> { @cook.ingredients.count }, 1 do
      post recipes_path, headers: submitted_from(recipes_path), params: { recipe: {
        name: "Pancakes",
        recipe_steps_attributes: { "0" => { instruction: "Whisk everything" } },
        recipe_ingredients_attributes: { "0" => { ingredient_name: "flour", quantity: "200", unit_name: "g" },
                                         "1" => { ingredient_name: "Maple syrup", quantity: "1", unit_name: "pcs" } }
      } }
    end
    pancakes = @cook.recipes.find_by!(name: "Pancakes")
    assert_equal [ ingredients(:flour).id, @cook.ingredients.find_by!(name: "Maple syrup").id ].sort, pancakes.recipe_ingredients.map(&:ingredient_id).sort
    follow_redirect!
    assert_select ".recipe-card__name", text: "Pancakes"
    assert_toast I18n.t("recipes.notices.created")
  end

  # Every request is watched for N+1 queries (test_helper.rb): a form's lines
  # are read, checked and made together, however many there are.
  test "a recipe of many lines, known and new to the pantry, is saved and edited in one go" do
    lines = [ %w[flour 200 g], %w[Eggs 2 pcs], %w[Sugar 50 g], %w[Salt 1 g], %w[Butter 30 g], %w[Milk 250 ml] ]
    fields = lines.each_with_index.to_h { |(name, quantity, unit), i| [ i.to_s, { ingredient_name: name, quantity: quantity, unit_name: unit } ] }

    assert_difference -> { @cook.ingredients.count }, 4 do
      post recipes_path, as: :turbo_stream, params: { recipe: { name: "Crêpes", recipe_ingredients_attributes: fields } }
    end
    crepes = @cook.recipes.find_by!(name: "Crêpes")
    assert_equal %w[Butter Eggs Flour Milk Salt Sugar], crepes.recipe_ingredients.map { _1.ingredient.name }.sort

    edits = crepes.recipe_ingredients.each_with_index.to_h { |line, i| [ i.to_s, { id: line.id, ingredient_name: "Oat #{line.ingredient.name.downcase}", quantity: "3", unit_name: "kg" } ] }
    assert_difference -> { @cook.ingredients.count }, 6 do
      patch recipe_path(crepes), as: :turbo_stream, params: { recipe: { name: "Crêpes", recipe_ingredients_attributes: edits } }
    end
    assert_equal [ "Oat butter", "Oat eggs", "Oat flour", "Oat milk", "Oat salt", "Oat sugar" ], crepes.reload.recipe_ingredients.map { _1.ingredient.name }.sort
  end

  test "a recipe needs a name" do
    assert_no_difference -> { Recipe.count } do
      post recipes_path, as: :turbo_stream, params: { recipe: { name: "" } }
    end
    assert_response :unprocessable_content
    assert_select "turbo-stream[action=update][target=modals] form[action=?]", recipes_path
    assert_form_error "Name can't be blank"
    assert_select ".field.is-invalid input#recipe_name[aria-describedby=recipe_name_error]"
    assert_select ".field__error#recipe_name_error", text: "Name can't be blank"
  end

  test "an ingredient row it refused is marked and says why; the summary says which row" do
    post recipes_path, as: :turbo_stream, params: { recipe: { name: "Bread", recipe_ingredients_attributes: {
      "0" => { ingredient_name: "Flour", quantity: "500" },
      "1" => { ingredient_name: "Salt", quantity: "0" }
    } } }

    assert_response :unprocessable_content
    assert_form_error "Ingredients, row 2: Quantity must be greater than 0"
    rows = css_select("[data-nested-fields-target=container] .recipe-ingredient-row")
    assert_equal([ false, true ], rows.map { _1.classes.include?("is-invalid") })
    assert_equal "Quantity must be greater than 0", rows.last.at_css(".nested-fields__error").text
    assert_equal "true", rows.last.at_css("input[name$='[quantity]']")["aria-invalid"]
    assert_nil rows.last.at_css("input[name$='[ingredient_name]']")["aria-invalid"]
  end
end
