# frozen_string_literal: true

require "test_helper"

class Reports::Pantry::AttentionItemsTest < ActiveSupport::TestCase
  setup do
    @profile = profiles(:carol)
    @today = Date.new(2025, 3, 15)
  end

  test "a planned meal short on ingredients needs attention, opening its day" do
    pantry_ingredient(@profile, "Flour", quantity: 0.2)
    bread = recipe_with(@profile, "Bread", [ "Flour", 1, "kg" ])
    day = meal_on(@profile, @today + 1, recipes: [ bread ])

    assert_equal([ [ :meal_short_on_ingredients, day, { ingredients: "Flour" } ] ], attention.map { [ _1.kind, _1.occurrence, _1.words ] })
  end

  test "a meal whose day has passed and isn't marked needs attention however long ago; one eaten, skipped or cancelled doesn't" do
    meal_on(@profile, @today - 90, title: "Lasagna")
    meal_on(@profile, @today - 2, title: "Eaten", status: :completed)
    meal_on(@profile, @today - 2, title: "Ate out instead", status: :skipped)

    assert_equal([ [ :unrecorded_meal, "Lasagna", @today - 90 ] ], attention.map { [ _1.kind, _1.subject, _1.date ] })
  end

  private

  def attention = dashboard.attention.to_a

  def dashboard
    Reports::Pantry::Dashboard.new(audience: audience_for(@profile), period: Reports::Period.recent(today: @today), today: @today)
  end
end
