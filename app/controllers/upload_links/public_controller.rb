# frozen_string_literal: true

# /s/:token — a public link: the file for whoever has it, no account needed:
#   show     what the file is and a Download button (a password field when
#            the link has one); a link that is spent, expired or revoked
#            says which (410), useful to whoever holds it and harmless with
#            256-bit tokens; a token that matches nothing is a 404
#   create   the press: the password checked (ten wrong ones close the
#            link), the download counted (UploadLink#consume!), then on to
#            the file by a ticket
#   file     the bytes, by the ticket the press gave: good for an hour and
#            only in the session that pressed, so a download cut short is
#            resumed without counting again, and the ticket's address passed
#            on to anyone else opens nothing
# Every press and every refusal goes on the file's trail. Rate limited by
# address: nobody guesses tokens or passwords here.
class UploadLinks::PublicController < ApplicationController
  include TokenInAddress

  without_authorization "public: whoever holds a link's token (UploadLink), rate limited by address", only: %i[show create file]

  TICKET_PURPOSE = :upload_link_file
  PRESSED = "upload_link_presses"
  PRESSES_KEPT = 5

  skip_before_action :authenticate_profile!
  rate_limit to: 30, within: 1.minute, with: -> { too_many_tries }
  rate_limit to: 10, within: 10.minutes, only: :create, with: -> { too_many_tries }

  def show
    link = find_link
    return gone(link) unless link&.usable?

    render Views::UploadLinks::Public::Show.new(link: link, token: params[:token], error: nil)
  end

  def create
    link = find_link
    return gone(link) unless link&.usable?

    if link.protected? && !link.authenticate(params[:password].to_s)
      link.refuse_password!(request:)
      return gone(link) if link.revoked?

      return render Views::UploadLinks::Public::Show.new(link: link, token: params[:token], error: t("upload_links.public.wrong_password")), status: :unprocessable_content
    end
    return gone(link.reload) unless link.consume!

    UploadActivity.record(link.upload, :link_downloaded, link: link, request: request)
    redirect_to public_upload_link_file_path(params[:token], t: ticket_for(link)), status: :see_other
  end

  def file
    link = find_link
    claim = verifier.verified(params[:t].to_s, purpose: TICKET_PURPOSE)
    return gone(link) unless link && claim.present? && claim == [ link.id, pressed[link.id.to_s] ] && link.continuation_allowed?

    response.set_header("Cache-Control", "private, no-store")
    send_file link.upload.path, filename: link.upload.name, type: link.upload.content_type || "application/octet-stream", disposition: "attachment"
  end

  private

  def find_link = UploadLink.includes(upload: :profile).find_by_token(params[:token])

  # A ticket for this press: the link and a nonce the session keeps too, so
  # it opens the file only here. The session remembers the last few presses.
  def ticket_for(link)
    nonce = SecureRandom.hex(16)
    session[PRESSED] = pressed.merge(link.id.to_s => nonce).to_a.last(PRESSES_KEPT).to_h
    verifier.generate([ link.id, nonce ], purpose: TICKET_PURPOSE, expires_in: UploadLink::CONTINUATION_WINDOW)
  end

  def pressed = session[PRESSED] || {}

  def verifier = Rails.application.message_verifier(:upload_links)

  # Why there is nothing here: the link's own state when it is spent,
  # expired or revoked, else `missing`, for a token that matches nothing, a
  # file not ready, or a ticket that doesn't hold: a stranger can't tell
  # those apart.
  def gone(link)
    reason = link && !link.upload.ready? ? :missing : (link&.state || :missing)
    reason = :missing if reason == :active
    render Views::UploadLinks::Public::Gone.new(reason: reason), status: (reason == :missing ? :not_found : :gone)
  end

  # Whoever holds the link sees a page that says why, not the app's toast:
  # they have no page of the app to stand on.
  def too_many_tries
    render Views::UploadLinks::Public::Gone.new(reason: :too_many), status: :too_many_requests
  end
end
