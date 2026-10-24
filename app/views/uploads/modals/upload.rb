# frozen_string_literal: true

# The upload modal: drop files on it or pick them, and watch each go up —
# in chunks, resumable, one file at a time (uploader_controller.js). The
# queue's rows are made from the template here. Closing the modal stops
# what is still going; the controller asks first.
class Views::Uploads::Modals::Upload < Views::Base
  # space_left: the bytes the household may still upload (Uploads::Quota#left).
  def initialize(space_left:)
    @space_left = space_left
  end

  def view_template
    render Components::Modal.new(size: :medium, section: :files) do |modal|
      modal.modal_header(title: t("uploads.uploader.title"), subtitle: t("uploads.uploader.subtitle", left: size(@space_left)), icon: "fa-cloud-arrow-up")
      modal.modal_body { uploader }
      # Each file is kept as soon as it is up, so leaving cancels nothing that is done.
      modal.modal_footer(dismiss: t("modal.done"))
    end
  end

  private

  def uploader
    div(class: "uploader", data: {
          controller: "uploader", uploader_create_url_value: uploads_path,
          uploader_chunk_size_value: Upload::CHUNK_SIZE, uploader_results_frame_value: Views::Uploads::List::FRAME_ID,
          uploader_words_value: words.to_json, uploader_confirm_dialog_outlet: "##{Components::ConfirmDialog::ID}",
          action: "dragover->uploader#dragOver dragleave->uploader#dragLeave drop->uploader#drop"
        }) do
      label(class: "uploader__drop", data: { uploader_target: "drop" }) do
        render Components::Icon.new("fa-cloud-arrow-up", class: "uploader__drop-icon")
        span(class: "uploader__drop-text") { t("uploads.uploader.drop") }
        span(class: "uploader__drop-hint") { t("uploads.uploader.drop_hint") }
        input(type: "file", multiple: true, class: "uploader__input", data: { uploader_target: "input", action: "change->uploader#pick" })
      end
      ul(class: "uploader__queue", data: { uploader_target: "queue" })
      p(class: "uploader__note") { t("uploads.uploader.closing_stops") }
      template(data: { uploader_target: "template" }) { item_template }
    end
  end

  def item_template
    li(class: "uploader__item", data: { state: "queued" }) do
      render Components::Icon.new("fa-file", class: "uploader__item-icon")
      div(class: "uploader__item-main") do
        span(class: "uploader__item-name", data: { role: "name" })
        span(class: "uploader__item-meta", role: "status", data: { role: "status" })
        div(class: "progress-bar", role: "progressbar", aria: { valuemin: 0, valuemax: 100, valuenow: 0 }, data: { role: "bar" }) { span(class: "progress-bar__fill") }
        span(class: "uploader__item-stats", data: { role: "stats" })
      end
      div(class: "uploader__item-actions") do
        render Components::ItemAction.new(icon: "fa-pause", label: t("uploads.uploader.pause"), data: { action: "uploader#pause", role: "pause" })
        render Components::ItemAction.new(icon: "fa-play", label: t("uploads.uploader.resume"), data: { action: "uploader#resume", role: "resume" })
        render Components::ItemAction.new(icon: "fa-xmark", label: t("uploads.uploader.cancel"), data: { action: "uploader#cancel", role: "cancel" }, danger: true)
      end
    end
  end

  # What the controller says, in the viewer's language.
  def words
    states = %w[queued uploading processing ready paused failed cancelled].index_with { |state| t("uploads.uploader.states.#{state}") }
    # %{…} left in for the controller to fill.
    stats = %w[progress speed eta_seconds eta_minutes eta_hours].index_with { |key| t("uploads.uploader.stats.#{key}") }
    states.merge(stats).merge(
      "retrying" => t("uploads.uploader.states.retrying"), "background" => t("uploads.uploader.states.background"),
      "closing" => t("uploads.uploader.confirm_close"), "stop" => t("uploads.uploader.stop"), "keep" => t("uploads.uploader.keep"),
      "failed_with" => t("uploads.uploader.failed_with"), "gone" => t("uploads.uploader.gone"),
      "row" => t("uploads.status.uploading", percent: "%{percent}")
    )
  end

  def size(bytes) = ActiveSupport::NumberHelper.number_to_human_size(bytes, locale: I18n.locale)
end
