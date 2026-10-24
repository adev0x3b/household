# frozen_string_literal: true

require "test_helper"

# A form's errors in the words of its labels: a row's error names its list
# and its row, never the path Rails builds for it.
class Forms::ErrorsTest < ActiveSupport::TestCase
  test "a recipe's bad rows are named by their list and their place in it, in every language" do
    recipe = recipes(:roast_chicken)
    rows = { "0" => { ingredient_name: "", quantity: "0" }, "1" => { ingredient_name: "Salt", quantity: "-1" } }
    recipe.assign_attributes(recipe_ingredients_attributes: rows)
    recipe.validate

    assert_equal [
      "Ingredients, row 2: Ingredient can't be blank",
      "Ingredients, row 2: Quantity must be greater than 0",
      "Ingredients, row 3: Quantity must be greater than 0"
    ], Forms::Errors.new(recipe).sentences
    I18n.with_locale(:it) do
      assert_equal "Ingredienti, riga 2: Ingrediente non può essere vuoto", Forms::Errors.new(recipe).sentences.first
    end
  end

  test "a new dose names its own fields and the supply it uses, though the form's record was rebuilt" do
    needles = supply_purchase!(profile: profiles(:alice), name: "Needles", quantity: 100).supply
    form = Occurrences::FormSave.for("Medication").new(actor: profiles(:alice), params: ActionController::Parameters.new(
      medication: { title: "B12", date: "2026-09-24", details_attributes: {
        kind: "injection", supply_uses_attributes: { "0" => { supply_id: needles.id, quantity: "0" } }
      } },
      event: { frequency: "weekly", interval: 1 }
    ).permit!)

    assert_not form.save
    assert_equal [ "Supplies used: Quantity must be greater than 0", "Area can't be blank", "Side can't be blank" ],
                 Forms::Errors.new(form.record).sentences
  end

  test "the series' fields are named as the day's form names them" do
    form = Occurrences::FormSave.for("Medication").new(actor: profiles(:alice), params: ActionController::Parameters.new(
      medication: { title: "Amoxicillin", date: "2026-09-24", details_attributes: { kind: "pill" } },
      event: { frequency: "daily", interval: 1, ends: "next Tuesday" }
    ).permit!)

    assert_not form.save
    assert_equal [ "Repeats needs the day it ends" ], Forms::Errors.new(form.record).sentences
  end

  test "a list with one row on the form is not numbered" do
    supply = Supply.new(profile: profiles(:alice), name: "Swabs", unit_label: "pcs",
                        supply_purchases_attributes: [ { quantity_purchased: "-1", purchased_on: Date.current } ])
    supply.validate

    assert_includes Forms::Errors.new(supply).sentences, "First purchase: Quantity purchased must be greater than 0"
  end

  test "the record's own errors read as Rails words them, a sentence on the whole record as it is" do
    book = Book.new(profile: profiles(:alice), cover_url: "https://example.com/cover.jpg")
    book.validate
    book.errors.add(:base, "Something about the whole book.")

    sentences = Forms::Errors.new(book).sentences
    assert_includes sentences, "Title can't be blank"
    assert_includes sentences, "Cover is invalid"
    assert_includes sentences, "Something about the whole book."
  end

  test "a field's errors are found by its path on the form's record, and a row's by its place in the list" do
    recipe = recipes(:roast_chicken)
    recipe.assign_attributes(name: "", recipe_ingredients_attributes: { "0" => { ingredient_name: "", quantity: "0" } })
    recipe.validate
    words = Forms::Errors.new(recipe)

    assert_equal [ "Name can't be blank" ], words.for(:name)
    assert_empty words.for(:recipe_ingredients)
    rows = words.rows(:recipe_ingredients)
    assert_equal [ 1 ], rows.keys
    assert_equal [ "Ingredient can't be blank", "Quantity must be greater than 0" ], rows[1].sentences
    assert_equal [ [ "Quantity must be greater than 0" ], [] ], [ rows[1].for(:quantity), rows[1].for(:unit) ]
    assert_not rows[0].any?
  end

  test "a kind's field on a day's form is found under the details" do
    form = Occurrences::FormSave.for("Medication").new(actor: profiles(:alice), params: ActionController::Parameters.new(
      medication: { title: "B12", date: "2026-09-24", details_attributes: { kind: "injection" } },
      event: { frequency: "weekly", interval: 1 }
    ).permit!)
    form.save

    assert_equal [ "Side can't be blank" ], Forms::Errors.new(form.record).for(:"details.side")
  end
end
