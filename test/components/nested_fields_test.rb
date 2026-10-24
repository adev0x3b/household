# frozen_string_literal: true

require "test_helper"

# The rows a form adds and takes away one at a time, as nested_fields_controller.js
# expects them: the rows, the template, the button, and what each row carries.
class Components::NestedFieldsTest < ActiveSupport::TestCase
  Step = Struct.new(:id) do
    def persisted? = !id.nil?
  end

  test "it draws the controller's element with the rows, the template and the button that adds a row" do
    html = render_fields { |fields| fields.rows { row(fields, index: 1) } }

    assert_equal "nested-fields", html.at_css("[data-controller=nested-fields]")["class"]
    assert_equal "recipe-steps-field__rows", html.at_css("[data-nested-fields-target=container]")["class"]
    assert_equal "Add a step", html.at_css("button.add-row-button[data-action='click->nested-fields#add']").text.strip
    assert_equal "recipe[recipe_steps_attributes][1]", html.at_css(".recipe-step-row span").text
  end

  test "headings sit over the fields in the row's own layout, read once by each field instead" do
    html = render_fields { |fields| fields.headings([ "Step", "recipe-step-row__field" ]) }
    headings = html.at_css(".recipe-step-row.nested-fields__headings[aria-hidden=true]")

    assert_equal "Step", headings.at_css("span.recipe-step-row__field").text
    assert headings.at_css("span.nested-fields__spacer"), "a spacer stands where each row has its remove button"
  end

  test "the template holds a row the controller numbers on the way in" do
    html = render_fields do |fields|
      fields.template { row(fields, index: Components::NestedFields::NEW_ROW) }
    end
    template = html.at_css("template[data-nested-fields-target=template]")

    assert_equal "recipe[recipe_steps_attributes][NEW_RECORD]", template.at_css(".recipe-step-row span").text
  end

  test "a saved row names its id and carries the flag that deletes it; a new row has no id" do
    html = render_fields do |fields|
      fields.rows do
        row(fields, index: 7, record: Step.new(7))
        row(fields, index: -42, record: Step.new(nil))
      end
    end
    saved, fresh = html.css("[data-nested-fields-target=row]")

    assert_equal "7", saved.at_css("input[name='recipe[recipe_steps_attributes][7][id]']")["value"]
    assert_equal "false", saved.at_css("input[name='recipe[recipe_steps_attributes][7][_destroy]'][data-nested-fields-target=destroyField]")["value"]
    assert_nil fresh.at_css("input[name$='[id]']")
    assert fresh.at_css("input[name='recipe[recipe_steps_attributes][-42][_destroy]']")
  end

  test "a row can name its record otherwise, as a day's form names the day's row and the series'" do
    inputs = [ { type: "hidden", name: "meal[x][3][id]", value: "3", data: { apply_to_scope: "day" } } ]
    html = render_fields { |fields| fields.rows { row(fields, index: 3, id_inputs: inputs) } }

    assert_equal "day", html.at_css("input[name='meal[x][3][id]']")["data-apply-to-scope"]
  end

  test "each row ends with the button that removes it, red for a row the server deletes" do
    html = render_fields { |fields| fields.rows { row(fields, index: 1) } }
    button = html.at_css("[data-nested-fields-target=row] button.item-action")

    assert_equal [ "Remove step", "click->nested-fields#remove" ], [ button["aria-label"], button["data-action"] ]
    assert_includes button.classes, "item-action--danger"
  end

  test "a list saved as a whole has neither id nor flag, and its remove button is quiet" do
    html = render_fields(saved_whole: true, danger: false) { |fields| fields.rows { row(fields, index: 0, record: Step.new(5)) } }
    row = html.at_css("[data-nested-fields-target=row]")

    assert_empty row.css("input[type=hidden]")
    assert_not_includes row.at_css("button.item-action").classes, "item-action--danger"
  end

  test "a row's index is its id, or a negative number for one not saved yet" do
    fields = build

    assert_equal 7, fields.index_of(Step.new(7))
    assert_operator fields.index_of(Step.new(nil)), :<, 0
  end

  test "a row the server refused is marked and says why under its fields, which point to it; the template is not counted" do
    recipe = recipes(:roast_chicken)
    recipe.assign_attributes(recipe_ingredients_attributes: { "0" => { ingredient_name: "Salt", quantity: "0" } })
    recipe.validate
    html = render_fields(errors: Forms::Errors.new(recipe).rows(:recipe_ingredients)) do |fields|
      fields.template { quantity_row(fields, index: Components::NestedFields::NEW_ROW) }
      fields.rows { [ 4, -9 ].each { |index| quantity_row(fields, index: index) } }
    end
    kept, refused = html.css("[data-nested-fields-target=container] [data-nested-fields-target=row]")

    assert_not_includes kept.classes, "is-invalid"
    assert_nil kept.at_css("input[name$='[quantity]']")["aria-invalid"]
    assert_includes refused.classes, "is-invalid"
    line = refused.at_css(".nested-fields__error")
    assert_equal [ "recipe_recipe_steps_attributes_-9_error", "Quantity must be greater than 0" ], [ line["id"], line.text ]
    quantity = refused.at_css("input[name$='[quantity]']")
    assert_equal [ "true", line["id"] ], [ quantity["aria-invalid"], quantity["aria-describedby"] ]
    assert_nil html.at_css("template .is-invalid")
  end

  private

  def build(**options)
    Components::NestedFields.new(rows_class: "recipe-steps-field__rows", row_class: "recipe-step-row",
                                 prefix: ->(index) { "recipe[recipe_steps_attributes][#{index}]" },
                                 add_label: "Add a step", remove_label: "Remove step", **options)
  end

  def render_fields(**options, &) = Nokogiri::HTML5.fragment(build(**options).call(&))

  # A row whose one field shows the prefix it was given.
  def row(fields, **options) = fields.row(**options) { |prefix| fields.span { prefix } }

  # A row whose one field is a quantity, carrying what the row says of it.
  def quantity_row(fields, **options)
    fields.row(**options) { |prefix, row| fields.input(name: "#{prefix}[quantity]", aria: { label: "Quantity", **row.aria(:quantity) }) }
  end
end
