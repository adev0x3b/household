# frozen_string_literal: true

# The modal that names a new analyte, or renames one.
class Views::Analytes::Modals::Form < Views::Base
  def initialize(analyte:, url:)
    @analyte = analyte
    @url = url
  end

  def view_template
    render Components::Modal.new(size: :small, section: :healthcare) do |modal|
      modal.modal_header(
        title: modal_title,
        icon: "fa-ruler"
      )

      render Components::Form.new(
        record: @analyte,
        url: @url,
        submit_text: submit_text,
        modal: modal
      ) do |f|
        render_name_field(f)
      end
    end
  end

  private

  def modal_title
    @analyte.persisted? ? t("analytes.form.edit_title") : t("analytes.form.new_title")
  end

  def submit_text
    @analyte.persisted? ? t("analytes.form.update") : t("analytes.form.create")
  end

  def render_name_field(f)
    form_field(f, :name, label: t("analytes.form.name_label")) do |field|
      f.text_field :name,
                   class: "input is-medium",
                   placeholder: t("analytes.form.name_placeholder"),
                   autofocus: true,
                   required: required_attribute?(@analyte, :name), aria: field.aria
    end
  end
end
