# frozen_string_literal: true

require "test_helper"

# One field of a form: its label tied to its control, the required mark the
# modal's form reads, and what helps fill it in.
class Components::FieldTest < ActiveSupport::TestCase
  # A field drawn the way a form draws it, with the block as its control.
  class Drawn < Views::Base
    def initialize(**options) = @options = options

    def view_template
      render Components::Field.new(label: "Name", control_id: "recipe_name", **@options) do |field|
        input(type: "text", id: "recipe_name", class: "input", aria: field.aria)
      end
    end
  end

  # A field of a record's form, required as the record's validations say.
  class OfRecord < Views::Base
    include Phlex::Rails::Helpers::FormFor

    def initialize(record:, attribute:) = (@record, @attribute = record, attribute)

    def view_template
      form_for(@record, url: "/recipes") do |f|
        form_field(f, @attribute, label: "Field") { |field| f.text_field @attribute, class: "input", aria: field.aria }
      end
    end
  end

  test "the label names its control, which is drawn inside Bulma's control" do
    field = parse(Drawn.new)

    assert_equal "recipe_name", field.at_css("label.label")["for"]
    assert field.at_css(".field > .control > input#recipe_name")
    assert_empty field.css(".modal__required-indicator, .help")
  end

  test "a required field's label is marked for the eye and for a screen reader" do
    label = parse(Drawn.new(required: true)).at_css("label")

    assert_equal %w[label label--required], label.classes
    assert label.children.first.text.end_with?(" "), "a page's label is plain text, and needs a space before its mark"
    assert_equal "true", label.at_css(".modal__required-indicator")["aria-hidden"]
    assert_equal I18n.t("modal.required_screen_reader"), label.at_css(".is-sr-only").text
  end

  test "every field keeps a hidden line for the modal's form to say it is missing" do
    line = parse(Drawn.new).at_css(".field > .modal__field-tooltip")

    assert line.has_attribute?("hidden")
    assert_empty line.text
    assert_equal "recipe_name_missing", line["id"], "the control points to it while it shows"
  end

  test "what was refused is said under the control, before what helps, and the control points to it" do
    field = parse(Drawn.new(errors: [ "Name can't be blank" ], help: "As on the package")).at_css(".field")

    assert_includes field.classes, "is-invalid"
    assert_equal [ "Name can't be blank", "As on the package" ], field.css(".field__error p, .help").map(&:text)
    assert_equal "recipe_name_error", field.at_css(".field__error")["id"]
    assert_equal({ "aria-invalid" => "true", "aria-describedby" => "recipe_name_error" },
                 field.at_css("input").to_h.slice("aria-invalid", "aria-describedby"))
  end

  test "a field with nothing refused is not marked, and its control carries nothing for it" do
    field = parse(Drawn.new).at_css(".field")

    assert_not_includes field.classes, "is-invalid"
    assert_nil field.at_css(".field__error")
    assert_nil field.at_css("input")["aria-invalid"]
  end

  test "a select is wrapped full width, and a field with its own controls draws them alone" do
    assert parse(Drawn.new(select: true)).at_css(".control > .select.is-fullwidth > input")

    field = parse(Drawn.new(control: false))
    assert_nil field.at_css(".control")
    assert field.at_css(".field > input#recipe_name")
  end

  test "a hidden label is kept for screen readers, with data of the caller's own" do
    hidden = Drawn.new(label_hidden: true, label_data: { appointment_form_target: "counterpartLabel" })
    label = parse(hidden).at_css("label")

    assert_equal %w[label is-sr-only], label.classes
    assert_equal "counterpartLabel", label["data-appointment-form-target"]
  end

  test "the field's own classes and attributes go on its wrapper" do
    wrapped = Drawn.new(class: "form-apply-to", hidden: true, data: { transaction_form_target: "counterpartyTextSection" })
    field = parse(wrapped).at_css("div")

    assert_equal %w[field form-apply-to], field.classes
    assert field.has_attribute?("hidden")
    assert_equal "counterpartyTextSection", field["data-transaction-form-target"]
  end

  test "a record's field is required when the record validates its presence, and its label names the control" do
    name = parse(OfRecord.new(record: Recipe.new, attribute: :name)).at_css("label")
    description = parse(OfRecord.new(record: Recipe.new, attribute: :description)).at_css("label")

    assert_equal [ "recipe_name", true ], [ name["for"], name.classes.include?("label--required") ]
    assert_not_includes description.classes, "label--required"
  end

  test "a record's field says what the record refused in it" do
    recipe = Recipe.new(profile: profiles(:alice)).tap(&:validate)
    field = parse(OfRecord.new(record: recipe, attribute: :name)).at_css(".field")

    assert_equal "Name can't be blank", field.at_css(".field__error").text
    assert_equal "recipe_name_error", field.at_css("input#recipe_name")["aria-describedby"]
  end

  private

  def parse(view) = Nokogiri::HTML5.fragment(ApplicationController.render(view, layout: false))
end
