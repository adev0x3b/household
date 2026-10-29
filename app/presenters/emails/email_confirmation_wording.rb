# frozen_string_literal: true

module Emails
  # The link that confirms an address (AccountMailer#email_confirmation).
  class EmailConfirmationWording < Wording
    # address: the one to confirm; url: the link's page, where a press with the password confirms.
    def initialize(profile, address:, url:)
      super(profile)
      @address = address
      @url = url
    end

    def subject = I18n.t("emails.email_confirmation.subject")

    def paragraphs = [ I18n.t("emails.email_confirmation.body", address: @address, hours: Profile::EMAIL_CONFIRMATION_FOR.in_hours.to_i) ]

    def action = Action.new(label: I18n.t("emails.email_confirmation.action"), url: @url)

    def closing = I18n.t("emails.email_confirmation.closing")
  end
end
