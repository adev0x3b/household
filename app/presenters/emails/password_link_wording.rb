# frozen_string_literal: true

module Emails
  # A link to set a new password, asked for on the sign-in page
  # (AccountMailer#password_link).
  class PasswordLinkWording < Wording
    # url: the page that sets the password.
    def initialize(profile, url:)
      super(profile)
      @url = url
    end

    def subject = I18n.t("emails.password_link.subject")

    def paragraphs
      [ I18n.t("emails.password_link.body", username: @profile.username, minutes: Profile::SHORT_PASSWORD_LINK_FOR.in_minutes.to_i) ]
    end

    def action = Action.new(label: I18n.t("emails.password_link.action"), url: @url)

    def closing = I18n.t("emails.password_link.closing")
  end
end
