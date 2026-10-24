# frozen_string_literal: true

# One file on the list: what it is, how big, whose, where its upload has
# got to, and its own actions: download and share one tap away, the rest
# behind "more". Replaced on its own when the file changes
# (Uploads::Broadcaster), removed when it goes.
class Views::Uploads::Row < Views::Base
  def self.dom_id(upload) = "upload_#{upload.id}"

  def initialize(upload:, viewer:)
    @upload = upload
    @viewer = viewer
  end

  def view_template
    div(id: self.class.dom_id(@upload), class: [ "upload-row", ("upload-row--pending" unless @upload.ready?) ]) do
      a(href: upload_path(@upload), class: "upload-row__icon", aria: { label: @upload.name }) { render Views::Uploads::Icon.new(@upload) }
      div(class: "upload-row__main") do
        a(href: upload_path(@upload), class: "upload-row__name") { @upload.name }
        p(class: "upload-row__meta") { meta }
        status unless @upload.ready?
      end
      div(class: "upload-row__actions") { actions }
    end
  end

  private

  def owner? = @upload.profile_id == @viewer.id

  def meta
    parts = [ size(@upload.byte_size), @upload.extension || t("uploads.kinds.#{@upload.kind}"), l(@upload.created_at.in_time_zone.to_date, format: :short) ]
    parts << t("uploads.row.owner", name: @upload.profile.display_name) unless owner?
    parts << t("uploads.row.shared_with", count: @upload.upload_shares.size) if owner? && @upload.upload_shares.any?
    plain parts.join(" · ")
  end

  def status
    if @upload.uploading?
      label = t("uploads.status.uploading", percent: @upload.percent)
      div(class: "upload-row__status") do
        render Components::StatusBadge.new(tone: :neutral, icon: "fa-cloud-arrow-up", label: label)
        render Components::ProgressBar.new(value: @upload.received_bytes, max: @upload.byte_size, label: label)
      end
    else
      div(class: "upload-row__status") { render Components::StatusBadge.new(tone: :neutral, icon: "fa-spinner", label: t("uploads.status.processing")) }
    end
  end

  def actions
    if @upload.ready?
      render Components::ItemAction.new(href: upload_downloads_path(@upload), icon: "fa-download", label: t("uploads.row.download"), download: true)
    end
    return unless owner?

    if @upload.ready?
      render Components::ItemAction.new(href: new_upload_share_path(upload_id: @upload.id), icon: "fa-share-nodes", label: t("uploads.row.share"), turbo_stream: true)
    end
    render Components::ItemMenu.new(label: t("uploads.row.more"), actions: menu_actions)
  end

  def menu_actions
    actions = []
    if Pundit.policy!(@viewer, @upload).link?
      actions << Components::Action.new(href: new_upload_upload_link_path(@upload), icon: "fa-link", label: t("uploads.row.link"), turbo_stream: true)
    end
    actions << Components::Action.new(href: edit_upload_path(@upload), icon: "fa-pen", label: t("uploads.row.rename"), turbo_stream: true)
    actions << Components::Action.new(href: upload_path(@upload), icon: "fa-trash", label: t("uploads.row.destroy"),
                                      method: :delete, confirm: t("uploads.confirm_destroy", name: @upload.name), danger: true)
  end

  def size(bytes) = ActiveSupport::NumberHelper.number_to_human_size(bytes, locale: I18n.locale)
end
