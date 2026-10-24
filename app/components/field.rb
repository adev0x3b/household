# frozen_string_literal: true

# One field of a form: its label, its control, what the server refused in
# it and what helps fill it in. The label names the control by its id
# (`control_id:`), so pressing the label focuses the control and a screen
# reader reads the label as its name. A required field's label is marked for
# the eye and for a screen reader; the control itself carries `required`,
# and the modal's form says under the field when it is still missing, on the
# line every field keeps for it.
#
#   render Components::Field.new(label: t("recipes.form.name_label"), control_id: f.field_id(:name), required: true,
#                                errors: Forms::Errors.new(recipe).for(:name)) do |field|
#     f.text_field :name, class: "input", required: true, aria: field.aria
#   end
#
# A field with errors is marked and says them under its control; the block
# is handed what its control carries then (`field.aria`), so a screen reader
# hears the control is wrong and what is wrong with it.
#
# The block is the control, drawn inside Bulma's `.control`. `select: true`
# wraps it in a full-width select, and `control: false` leaves the block to
# draw its own controls, such as a field with an addon button.
# `label_hidden: true` keeps the label for screen readers alone, where the
# placeholder already says it on screen.
class Components::Field < Components::Base
  def initialize(label:, control_id:, required: false, help: nil, errors: [], select: false, control: true,
                 label_hidden: false, label_data: {}, **attributes)
    @label = label
    @control_id = control_id
    @required = required
    @help = help
    @errors = errors
    @select = select
    @control = control
    @label_hidden = label_hidden
    @label_data = label_data
    @attributes = attributes
  end

  def view_template
    div(**@attributes.except(:class), class: [ "field", ("is-invalid" if invalid?), @attributes[:class] ]) do
      field_label
      if @control
        div(class: "control") { @select ? div(class: "select is-fullwidth") { yield(self) } : yield(self) }
      else
        yield(self)
      end
      div(class: "field__error", id: error_id) { @errors.each { |message| p { message } } } if invalid?
      p(class: "help") { @help } if @help
      p(class: "modal__field-tooltip", id: missing_id, hidden: true)
    end
  end

  # What the control carries: when the field has errors, that it is wrong
  # and where that is said.
  def aria = invalid? ? { invalid: "true", describedby: error_id } : {}

  def error_id = "#{@control_id}_error"

  # The line the modal's form fills when the field is required and still
  # empty, which the control points to then (modal_form_controller.js).
  def missing_id = "#{@control_id}_missing"

  private

  def invalid? = @errors.any?

  def field_label
    label(for: @control_id, class: label_classes, data: @label_data) do
      plain @label
      next unless @required

      # A modal's label is a flex row that spaces its parts itself and drops
      # this space; a page's label is plain text that needs it.
      whitespace
      span(class: "modal__required-indicator", aria: { hidden: "true" }) { t("modal.required_indicator") }
      span(class: "is-sr-only") { t("modal.required_screen_reader") }
    end
  end

  def label_classes = [ "label", ("label--required" if @required), ("is-sr-only" if @label_hidden) ]
end
