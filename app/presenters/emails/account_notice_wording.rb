# frozen_string_literal: true

module Emails
  # A notice that something changed on the account, when, and what to do if
  # the person didn't do it (AccountMailer): each kind words its own under
  # emails.<kind>, and leads to the account page.
  class AccountNoticeWording < Wording
    # at: when it happened, said on the person's clock whatever zone it
    # comes in.
    def initialize(profile, at:, account_url:)
      super(profile)
      @at = at
      @account_url = account_url
    end

    def subject = I18n.t("emails.#{key}.subject")

    def paragraphs
      [ I18n.t("emails.#{key}.body", address: @profile.email), I18n.t("emails.#{key}.when", time: I18n.l(@at.in_time_zone(@profile.zone), format: :long)), I18n.t("emails.#{key}.not_you") ]
    end

    def action = Action.new(label: I18n.t("emails.account_action"), url: @account_url)

    private

    def key = raise(NotImplementedError, "#{self.class.name} names its words")
  end
end
