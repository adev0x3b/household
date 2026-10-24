# frozen_string_literal: true

# One file: what is known about it (size, type, SHA-256 to check a copy
# against, when and by whom), and, for its owner, who it is shared with, its
# links, and everything that happened to it. Replaced as one unit when the
# file changes. Downloading and sharing it are the top bar's, with linking,
# renaming and deleting behind its "more", each for whoever may do it.
class Views::Uploads::Show < Views::Base
  include Phlex::Rails::Helpers::TurboStreamFrom

  def self.dom_id(upload) = "upload-#{upload.id}-page"

  # page: its links and its trail (Uploads::Page), shown to its owner.
  def initialize(upload:, viewer:, page:)
    @upload = upload
    @viewer = viewer
    @page = page
  end

  def page_title = @upload.name

  def navbar_controls
    policy = Pundit.policy!(@viewer, @upload)
    actions = []
    if policy.download?
      actions << Components::Action.new(href: routes.upload_downloads_path(@upload), icon: "fa-download", label: t("uploads.show.download"),
                                        download: true)
    end
    if SharePolicy.new(@viewer, @upload).share?
      actions << Components::Action.new(href: routes.new_upload_share_path(upload_id: @upload.id), icon: "fa-share-nodes",
                                        label: t("uploads.show.share"), turbo_stream: true)
    end
    if policy.link?
      actions << Components::Action.new(href: routes.new_upload_upload_link_path(@upload), icon: "fa-link",
                                        label: t("uploads.show.link"), turbo_stream: true)
    end
    if policy.update?
      actions << Components::Action.new(href: routes.edit_upload_path(@upload), icon: "fa-pen", label: t("uploads.show.rename"), turbo_stream: true)
    end
    if policy.destroy?
      actions << Components::Action.new(href: routes.upload_path(@upload), icon: "fa-trash", label: t("uploads.show.destroy"), method: :delete,
                                        confirm: t("uploads.confirm_destroy", name: @upload.name), danger: true)
    end
    Components::PageControls.new(actions: actions)
  end

  def view_template
    div(id: self.class.dom_id(@upload), class: "upload-show") do
      turbo_stream_from @viewer, :uploads
      render Components::PageHeader.new(title: @upload.name, back_href: uploads_path, back_label: t("uploads.show.back"))

      div(class: "upload-show__main") do
        div(class: "upload-show__icon") { render Views::Uploads::Icon.new(@upload) }
        div(class: "upload-show__details") do
          progress unless @upload.ready?
          facts
          shared_line
        end
      end

      owner_sections if owner?
    end
  end

  private

  def owner? = @upload.profile_id == @viewer.id

  def progress
    label = @upload.uploading? ? t("uploads.status.uploading", percent: @upload.percent) : t("uploads.status.processing")
    div(class: "upload-show__progress") do
      render Components::StatusBadge.new(tone: :neutral, icon: (@upload.uploading? ? "fa-cloud-arrow-up" : "fa-spinner"), label: label)
      render Components::ProgressBar.new(value: @upload.received_bytes, max: @upload.byte_size, label: label) if @upload.uploading?
    end
  end

  def facts
    dl(class: "upload-show__facts") do
      fact(:size) { size(@upload.byte_size) }
      fact(:type) { t("uploads.kinds.#{@upload.kind}") } if @upload.content_type
      fact(:checksum) { checksum } if @upload.checksum
      fact(:uploaded_on) { l(@upload.completed_at, format: :long) } if @upload.completed_at
      fact(:uploaded_by) { @upload.profile.display_name }
    end
  end

  def fact(key, &)
    div(class: "upload-show__fact") do
      dt { t("uploads.show.facts.#{key}") }
      dd(&)
    end
  end

  # The SHA-256, with a button to copy it: `sha256sum` on the download should say the same.
  def checksum
    div(class: "upload-show__checksum", data: { controller: "clipboard", clipboard_copied_value: t("uploads.show.copied") }) do
      input(type: "text", readonly: true, class: "input is-small upload-show__checksum-value", value: @upload.checksum,
            aria: { label: t("uploads.show.facts.checksum") }, data: { clipboard_target: "source", action: "focus->clipboard#select" })
      render Components::ItemAction.new(icon: "fa-copy", label: t("uploads.show.copy"), data: { action: "clipboard#copy", clipboard_target: "button" })
    end
  end

  def shared_line
    return if owner?

    p(class: "upload-show__shared") do
      render Components::Icon.new("fa-user-group")
      span { t("uploads.show.shared_by", name: @upload.profile.display_name) }
    end
  end

  def owner_sections
    return unless @upload.ready?

    section(class: "upload-show__section", aria: { label: t("uploads.show.shares") }) do
      h2(class: "upload-show__section-title") { t("uploads.show.shares") }
      render Views::Shares::List.new(thing: @upload, place: :page)
    end
    if Pundit.policy!(@viewer, @upload).link?
      section(class: "upload-show__section", aria: { label: t("uploads.show.links") }) do
        h2(class: "upload-show__section-title") { t("uploads.show.links") }
        render Views::UploadLinks::Panel.new(upload: @upload, links: @page.links)
      end
    end
    section(class: "upload-show__section", aria: { label: t("uploads.show.activity") }) do
      h2(class: "upload-show__section-title") { t("uploads.show.activity") }
      render Views::Uploads::Activity.new(entries: @page.activity, older: @page.older_activity)
    end
  end

  def size(bytes) = ActiveSupport::NumberHelper.number_to_human_size(bytes, locale: I18n.locale)
end
