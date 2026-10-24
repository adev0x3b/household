# frozen_string_literal: true

# The link just made, in a modal of its own wherever the form was opened
# (the list's "more" menu or the file's page): its address to copy, shown
# only now — the database keeps a digest — and what it allows.
class Views::UploadLinks::Modals::Created < Views::Base
  def initialize(link:, token:)
    @link = link
    @token = token
  end

  def view_template
    render Components::Modal.new(size: :small, section: :files) do |modal|
      modal.modal_header(title: t("upload_links.created.title"), subtitle: @link.upload.name, icon: "fa-link")
      modal.modal_body do
        div(class: "upload-links__fresh", data: { controller: "clipboard", clipboard_copied_value: t("upload_links.created.copied") }) do
          p(class: "upload-links__fresh-hint") { t("upload_links.created.hint") }
          div(class: "upload-links__fresh-row") do
            input(type: "text", readonly: true, class: "input upload-links__fresh-url", value: public_upload_link_url(@token),
                  aria: { label: t("upload_links.created.link") }, data: { clipboard_target: "source", action: "focus->clipboard#select" })
            render Components::ItemAction.new(icon: "fa-copy", label: t("upload_links.created.copy"), data: { action: "clipboard#copy", clipboard_target: "button" })
          end
        end
        p(class: "upload-link-form__note") { terms }
      end
      modal.modal_footer(dismiss: t("modal.done"))
    end
  end

  private

  def terms
    downloads = @link.max_downloads ? t("upload_links.form.downloads", count: @link.max_downloads) : t("upload_links.form.unlimited")
    parts = [ downloads, t("upload_links.panel.expires_on", date: l(@link.expires_at, format: :short)) ]
    parts << t("upload_links.panel.protected") if @link.protected?
    parts.join(" · ")
  end
end
