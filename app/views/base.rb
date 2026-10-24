# frozen_string_literal: true

# A page, or a part of one, rendered by a controller. A full page names
# itself and brings the top bar's controls with it, so its controller only
# has to hand it to `render_page` (NavbarPageControls).
class Views::Base < Components::Base
  # The page's name, for the browser tab: the same words as the page's own
  # h1 (Components::PageHeader). Nil for a view that is not a whole page.
  def page_title = nil

  # What the top bar holds for this page, usually Components::PageControls
  # with the search and the buttons that act on the whole page. Nil when the
  # page has none.
  def navbar_controls = nil

  private

  # The controller asks for the controls before the view renders, when the
  # route helpers that go through the view context are not available yet,
  # so the controls build their paths from the application's routes.
  def routes = Rails.application.routes.url_helpers

  # Whether the record can't be saved without the attribute: it is validated
  # as present or as a number, or its column is NOT NULL with no default. A
  # form object has no columns, only its validations.
  def required_attribute?(record, attribute, validation_attribute: attribute)
    validated = record.class.validators_on(validation_attribute).any? do |validator|
      validator.kind == :presence || (validator.kind == :numericality && validator.options[:allow_nil] != true)
    end
    return true if validated
    return false unless record.class.respond_to?(:columns_hash)

    column = record.class.columns_hash[validation_attribute.to_s]
    column.present? && !column.null && column.default.nil?
  end

  # A field for one of the record's attributes: its label tied to the
  # control the form builder draws for it, marked when the record requires
  # the attribute unless `required:` says otherwise, and saying what the
  # form's record refused in it.
  def form_field(f, attribute, label:, record: f.object, validation_attribute: attribute, required: nil, errors: nil, **, &)
    required = required_attribute?(record, attribute, validation_attribute: validation_attribute) if required.nil?
    errors ||= field_errors(f, attribute)

    render Components::Field.new(label: label, control_id: f.field_id(attribute), required: required, errors: errors, **, &)
  end

  # What the form's record refused in one of its fields. A form whose
  # builder draws another record's fields (a day's form, its kind's
  # details) says where that record's errors are kept.
  def field_errors(f, attribute) = Forms::Errors.new(f.object).for(attribute)
end
