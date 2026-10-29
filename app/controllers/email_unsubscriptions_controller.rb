# frozen_string_literal: true

# The link at the foot of every reminder mail and in its List-Unsubscribe
# header, for whoever holds it: no account needed, since mail is read
# where nobody may be signed in. Opening the page changes nothing, so a
# scanner that follows the link stops nothing; its button, or a mail
# client's one-click POST (RFC 8058), stops every reminder by email
# (Reminders::StopEmail). The token travels in the query, never the path.
class EmailUnsubscriptionsController < ApplicationController
  include TokenInAddress

  without_authorization "public: whoever holds a reminder mail's link (Profile's email_unsubscription token), rate limited by address",
                        only: %i[show create]

  skip_before_action :authenticate_profile!
  # A mail client's one-click POST carries no form token; the link's token,
  # which only the mail holds, is what a stranger can't send.
  skip_forgery_protection only: :create
  # Home rather than back, which may be this page again.
  rate_limit to: 20, within: 10.minutes, with: -> { rate_limited(to: root_path) }

  def show
    render_page Views::EmailUnsubscriptions::Show.new(token: token, state: state_of(profile))
  end

  # A mail client's one-click press hears only whether it was done: RFC 8058
  # forbids answering it with a redirect.
  def create
    unless profile
      return one_click? ? head(:unprocessable_content) : refuse(t("email_unsubscriptions.show.gone"))
    end

    Reminders::StopEmail.call(profile)
    return head(:ok) if one_click?

    toast_flash(:success, t("email_unsubscriptions.notices.stopped"))
    redirect_to email_unsubscription_path(token: token), status: :see_other
  end

  private

  def token = params[:token].to_s

  # The body a mail client posts from the List-Unsubscribe header (RFC 8058).
  def one_click? = params["List-Unsubscribe"] == "One-Click"

  def profile = (@profile ||= Profile.find_by_token_for(:email_unsubscription, token))

  # :gone when the link no longer works (the address changed, or it is too
  # old); else whether a reminder still comes by email.
  def state_of(profile)
    return :gone unless profile

    profile.event_reminders.where(by_email: true).exists? ? :emailed : :none
  end
end
