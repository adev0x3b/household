# frozen_string_literal: true

# Renaming a file: the name it is kept and given back under.
class Views::Uploads::Modals::Form < Views::Base
  def initialize(upload:, url:)
    @upload = upload
    @url = url
  end

  def view_template
    render Components::Modal.new(size: :small, section: :files) do |modal|
      modal.modal_header(title: t("uploads.form.title"), subtitle: t("uploads.form.subtitle"), icon: "fa-pen")

      render Components::Form.new(record: @upload, url: @url, submit_text: t("uploads.form.update"), modal: modal) do |f|
        form_field(f, :name, label: t("uploads.form.name_label")) do |field|
          f.text_field :name, class: "input is-medium", autofocus: true, required: true, maxlength: Upload::NAME_LENGTH, aria: field.aria
        end
      end
    end
  end
end
