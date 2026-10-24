# frozen_string_literal: true

# The rows a form adds and takes away one at a time (a lab result's values, a
# recipe's steps, what a dose draws on, a person's reminders), kept in step
# by nested_fields_controller.js: the rows there are, the template a new row
# is cloned from, and the button that adds one. The caller keeps its
# fieldset and legend and draws one row's fields; `row` wraps them with what
# every row needs.
#
#   render Components::NestedFields.new(rows_class: "recipe-steps-field__rows", row_class: "recipe-step-row",
#                                       prefix: ->(index) { "recipe[recipe_steps_attributes][#{index}]" },
#                                       add_label: t("recipes.form.steps.add"), remove_label: t("recipes.form.steps.remove")) do |fields|
#     fields.rows { steps.each { |step| step_row(fields, step, fields.index_of(step)) } }
#     fields.template { step_row(fields, RecipeStep.new, Components::NestedFields::NEW_ROW) }
#   end
#
#   def step_row(fields, step, index)
#     fields.row(record: step, index: index) do |prefix|
#       textarea(name: "#{prefix}[instruction]", …) { plain step.instruction }
#     end
#   end
#
# A row carries a `_destroy` flag, and a saved one names its id too, so
# removing a row hides it and tells the server, which deletes a saved row
# and drops a new one. A list saved as a whole (the reminders) has neither,
# and its row is taken out: `saved_whole: true`.
#
# What a form that didn't save refused in its rows comes as `errors:`, by
# each row's place in the list (Forms::Errors#rows). A row with errors is
# marked and says them on a line under its fields, and hands its block,
# beside the prefix, what each field carries then:
#
#   fields.row(record: entry, index: index) do |prefix, row|
#     input(name: "#{prefix}[quantity]", aria: { label: t("…"), **row.aria(:quantity) })
#   end
class Components::NestedFields < Components::Base
  # Where a new row's index goes in the template; the controller numbers it.
  NEW_ROW = "NEW_RECORD"

  def initialize(rows_class:, row_class:, prefix:, add_label:, remove_label:, saved_whole: false, danger: true, errors: {})
    @rows_class = rows_class
    @row_class = row_class
    @prefix = prefix
    @add_label = add_label
    @remove_label = remove_label
    @saved_whole = saved_whole
    @danger = danger
    @errors = errors
  end

  def view_template
    div(class: "nested-fields", data: { controller: "nested-fields" }) do
      yield(self) if block_given?
      render Components::AddRowButton.new(label: @add_label)
    end
  end

  # The rows are counted as they are drawn, so each finds its errors by its
  # place in the list; the template's row is not one of them.
  def rows(&)
    @position = 0
    div(class: @rows_class, data: { nested_fields_target: "container" }, &)
  ensure
    @position = nil
  end

  # A heading over each field of a row, for rows whose fields are told
  # apart only by where they sit (an analyte, its value, its unit). Each
  # column is its words and the class its fields have, so they line up;
  # each field still names itself to a screen reader.
  def headings(*columns)
    div(class: "#{@row_class} nested-fields__headings", aria: { hidden: "true" }) do
      columns.each { |words, field_class| span(class: field_class) { words } }
      span(class: "nested-fields__spacer")
    end
  end

  def template(&)
    super(data: { nested_fields_target: "template" }, &)
  end

  # A row's index is its id, or a negative number for one not saved yet:
  # strong parameters drops any other nested-attributes key.
  def index_of(record)
    record.persisted? ? record.id : -record.object_id
  end

  # One row, yielding the prefix its fields are named under. `id_inputs`
  # are the hidden inputs naming the record it stands for: the record's own
  # id by default; a day's form names the day's row and the series' row
  # (Occurrences::DetailsList).
  def row(index:, record: nil, id_inputs: nil)
    prefix = @prefix.call(index)
    marks = Row.new(next_row_errors, "#{prefix.gsub(/\]\[|[^-a-zA-Z0-9:.]/, "_").delete_suffix("_")}_error")
    div(class: [ @row_class, ("is-invalid" if marks.invalid?) ], data: { nested_fields_target: "row" }) do
      identify(record, prefix, id_inputs) unless @saved_whole
      yield prefix, marks
      render Components::ItemAction.new(icon: "fa-xmark", label: @remove_label, danger: @danger, data: { action: "click->nested-fields#remove" })
      div(class: "nested-fields__error", id: marks.line_id) { marks.sentences.each { |sentence| p { sentence } } } if marks.invalid?
    end
  end

  # A row's errors as its fields carry them: each field an error is about
  # says it is wrong and points to the line under the row that says why.
  class Row
    attr_reader :line_id

    def initialize(errors, line_id)
      @errors = errors
      @line_id = line_id
    end

    def invalid? = !@errors.nil? && @errors.any?
    def sentences = invalid? ? @errors.sentences : []

    # The fields an attribute is typed into, by the attributes it is
    # checked as (an ingredient by name and by id).
    def aria(*attributes)
      return {} unless invalid? && attributes.any? { |attribute| @errors.for(attribute).any? }

      { invalid: "true", describedby: @line_id }
    end
  end

  private

  def next_row_errors
    return if @position.nil?

    errors = @errors[@position]
    @position += 1
    errors
  end

  def identify(record, prefix, id_inputs)
    (id_inputs || own_id_inputs(record, prefix)).each { |attributes| input(**attributes) }
    input(type: "hidden", name: "#{prefix}[_destroy]", value: "false", data: { nested_fields_target: "destroyField" })
  end

  def own_id_inputs(record, prefix)
    return [] unless record&.persisted?

    [ { type: "hidden", name: "#{prefix}[id]", value: record.id } ]
  end
end
