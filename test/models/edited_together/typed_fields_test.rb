# frozen_string_literal: true

require "test_helper"

class EditedTogether::TypedFieldsTest < ActiveSupport::TestCase
  SENT = {
    "name" => "Roast", "description" => "For guests",
    "details_attributes" => { "id" => "4", "priority" => "high", "notes" => "Early" },
    "recipe_steps_attributes" => { "0" => { "id" => "7", "instruction" => "Roast it" }, "1" => { "instruction" => "Rest it" } }
  }.freeze

  def typed(*names) = EditedTogether::TypedFields.new(names, SENT, under: "recipe")

  test "a request that lists nothing never said" do
    fields = EditedTogether::TypedFields.new(nil, SENT, under: "recipe")

    assert_not fields.told?
    assert_empty fields.names
    nothing = typed("")
    assert_predicate nothing, :told?, "a list holding only the form's empty name says nothing was typed"
    assert_empty nothing.names
    assert_empty nothing.attributes
  end

  test "a record's own fields are kept one by one, under the record's key only" do
    assert_equal({ "description" => "For guests" }, typed("recipe[description]", "event[frequency]", "collection[name]").attributes)
  end

  test "a nested record keeps the fields typed in it and its id" do
    assert_equal({ "details_attributes" => { "priority" => "high", "id" => "4" } }, typed("recipe[details_attributes][priority]").attributes)
  end

  test "a list of rows is kept whole when anything in it was typed" do
    assert_equal SENT.slice("recipe_steps_attributes"), typed("recipe[recipe_steps_attributes][1][instruction]").attributes
  end

  test "only names count" do
    fields = EditedTogether::TypedFields.new([ "recipe[name]", { "recipe" => "description" } ], SENT, under: "recipe")

    assert_equal [ "recipe[name]" ], fields.names
  end
end
