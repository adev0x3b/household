# frozen_string_literal: true

# A record's form inside a modal: its errors above the fields, the fields
# the caller's block draws with the Rails form builder, and the Save button
# in the modal's footer, which sends nothing while a required field is
# missing and says which instead (modal_form_controller.js). A page's own
# form (settings, signing in) is a plain form_with instead.
#
#   render Components::Modal.new do |modal|
#     render Components::Form.new(record: recipe, url: recipes_path, modal: modal) do |f|
#       form_field(f, :name, label: t("recipes.form.name"))
#     end
#   end
class Components::Form < Components::Base
  include Phlex::Rails::Helpers::FormFor

  # The method is read off the record when not given (a saved one is
  # patched), the submit's words likewise. The form's data attributes join
  # the modal form's own, so a form can bring its own Stimulus controller.
  # The scope is the params key the fields post under, the record's own
  # unless given (a day of a series posts under Views::Occurrences::DayForm's).
  def initialize(record:, url:, modal:, method: nil, submit_text: nil, form_data: {}, scope: nil)
    @record = record
    @url = url
    @modal = modal
    @method = method || (record.persisted? ? :patch : :post)
    @submit_text = submit_text || default_submit_text
    @form_data = form_data
    @scope = scope
  end

  def view_template
    form_for(@record, as: @scope, url: @url, method: @method, html: form_html_options) do |f|
      @modal.modal_body do
        render Components::ErrorSummary.new(record: @record)
        # A record more than one person can edit goes back with the version
        # it was drawn at, so a save made after someone else's is refused.
        f.hidden_field(:lock_version) if @record.persisted? && @record.class.locking_enabled?
        render_typed_fields if edited_together?
        before_fields
        if read_only?
          fieldset(disabled: true, class: "modal__readonly") { yield(f) }
        else
          yield(f)
        end
      end

      # A form the viewer can only read has nothing to cancel.
      @modal.modal_footer(dismiss: read_only? ? t("modal.close") : t("modal.cancel")) do
        div(class: "modal__footer-main") do
          next if read_only?

          f.submit(submit_label, class: "modal__btn modal__btn--primary")
        end
      end
    end
  end

  private

  def form_html_options
    default_data = {
      controller: [ "modal-form", ("typed-fields" if edited_together?) ].compact.join(" "),
      action: [ "input->modal-form#refresh change->modal-form#refresh focusout->modal-form#leave " \
                "invalid->modal-form#invalid:capture submit->modal-form#beforeSubmit",
                ("submit->typed-fields#note" if edited_together?) ].compact.join(" "),
      modal_form_field_required_value: t("modal.field_required_hint"),
      # A form the server sent back refused has been sent once: every
      # field still missing says so from the start.
      modal_form_submitted_value: @record.errors.any?
    }

    merged_data = [ stimulus_data, @form_data ].reduce(default_data) do |data, extra|
      data.merge(extra) { |key, original, added| %i[controller action].include?(key) ? [ original, added ].compact.join(" ") : added }
    end

    # _top escapes the modal's turbo-frame so a redirect response (e.g. after
    # create/update) is a normal page visit instead of a frame-scoped fetch
    # that can't find a matching frame id and renders "Content missing".
    { "data-turbo": "true", "data-turbo-frame": "_top", class: "modal__form", data: merged_data }
  end

  # A form of something housemates edit together says which of its fields
  # were typed in (typed_fields_controller.js), so that a save refused
  # because someone saved meanwhile keeps only those over what they saved.
  # Shown again, it still names the fields typed before.
  def edited_together? = @record.is_a?(EditedTogether)

  def render_typed_fields
    @record.typed_fields&.names&.each { |name| input(type: "hidden", name: "typed_fields[]", value: name) }
  end

  # What a kind of form adds (Views::Occurrences::DayForm: a day of a series):
  # notices and choices before the fields, whether it is only to be read,
  # the submit's words, and its own Stimulus controllers.
  def before_fields = nil
  def read_only? = false
  def submit_label = @submit_text
  def stimulus_data = {}

  def default_submit_text
    if @record.persisted?
      t("form.update")
    else
      t("form.create")
    end
  end
end
