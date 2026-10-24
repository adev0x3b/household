# frozen_string_literal: true

# Making a link to a file for someone outside: how long it is good for,
# how many downloads it allows, and a password if wanted. The link itself
# comes back once, in a modal of its own (Views::UploadLinks::Modals::Created).
class Views::UploadLinks::Modals::Form < Views::Base
  def initialize(upload:)
    @upload = upload
  end

  def view_template
    render Components::Modal.new(size: :small, section: :files) do |modal|
      modal.modal_header(title: t("upload_links.form.title"), subtitle: t("upload_links.form.subtitle", name: @upload.name), icon: "fa-link")
      modal.modal_form(url: upload_upload_links_path(@upload), method: :post, scope: :upload_link, data: { turbo_stream: true }, class: "upload-link-form") do |f|
        modal.modal_body do
          choice(f, :lifetime_days, UploadLink::LIFETIMES.map { |days| [ t("upload_links.form.lifetimes", count: days), days ] }, UploadLink::DEFAULT_LIFETIME)
          choice(f, :max_downloads, UploadLink::LIMITS.map { |n| [ (n ? t("upload_links.form.downloads", count: n) : t("upload_links.form.unlimited")), (n || "unlimited") ] },
                 UploadLink::DEFAULT_LIMIT)
          render Components::Field.new(label: t("upload_links.form.password_label"), control_id: "upload_link_password",
                                       help: t("upload_links.form.password_help")) do
            f.password_field :password, class: "input", autocomplete: "new-password", minlength: UploadLink::PASSWORD_LENGTH.min,
                                        maxlength: UploadLink::PASSWORD_LENGTH.max, placeholder: t("upload_links.form.password_placeholder", min: UploadLink::PASSWORD_LENGTH.min)
          end
          p(class: "upload-link-form__note") { t("upload_links.form.shown_once") }
        end
        modal.modal_footer do
          div(class: "modal__footer-main") { f.submit t("upload_links.form.create"), class: "modal__btn modal__btn--primary" }
        end
      end
    end
  end

  private

  def choice(f, attribute, options, default)
    render Components::Field.new(label: t("upload_links.form.#{attribute}_label"), control_id: "upload_link_#{attribute}", select: true) do
      f.select attribute, options, { selected: default }
    end
  end
end
