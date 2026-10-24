# frozen_string_literal: true

# A file's public links: the modal to make one (how long it lasts, how
# many downloads, a password or not), the link itself — shown once in a
# modal of its own, the database keeps a digest — and revoking one. None
# where the installation has uploads off (UploadPolicy#link?).
class UploadLinksController < ApplicationController
  before_action :set_upload, only: %i[new create]

  def new
    authorize @upload, :link?

    render_modal(Views::UploadLinks::Modals::Form.new(upload: @upload), page: @upload)
  end

  def create
    authorize @upload, :link?

    given = params.fetch(:upload_link, {}).permit(:lifetime_days, :max_downloads, :password)
    lifetime = given[:lifetime_days].to_i.presence_in(UploadLink::LIFETIMES) || UploadLink::DEFAULT_LIFETIME
    limit = given[:max_downloads].to_s == "unlimited" ? nil : (given[:max_downloads].to_i.presence_in(UploadLink::LIMITS.compact) || UploadLink::DEFAULT_LIMIT)

    link, token = UploadLink.mint(upload: @upload, by: current_profile, lifetime_days: lifetime, max_downloads: limit, password: given[:password])
    if link.persisted?
      UploadActivity.record(@upload, :link_created, actor: current_profile, link: link, lifetime_days: lifetime, max_downloads: limit, protected: link.protected?)
      # The address goes in a modal, not the page's panel: the form may have
      # been opened from the list, where there is no panel to show it in.
      render turbo_stream: [
        redraw_modal(Views::UploadLinks::Modals::Created.new(link: link, token: token)),
        turbo_stream.replace(Views::UploadLinks::Panel.dom_id(@upload), links_panel(@upload))
      ]
    else
      refuse(link.errors.full_messages.to_sentence)
    end
  end

  # Revoked, not deleted: the trail keeps what it was.
  def destroy
    link = policy_scope(UploadLink).includes(:upload).find(params[:id])
    authorize link

    link.revoke!
    UploadActivity.record(link.upload, :link_revoked, actor: current_profile, link: link)
    render turbo_stream: [
      turbo_stream.replace(Views::UploadLinks::Panel.dom_id(link.upload), links_panel(link.upload)),
      toast(:success, t("upload_links.notices.revoked"))
    ]
  end

  private

  def set_upload
    @upload = policy_scope(Upload).includes(:upload_links).find(params[:upload_id])
  end

  def links_panel(upload) = Views::UploadLinks::Panel.new(upload: upload, links: Uploads::Page.new(upload).links)
end
