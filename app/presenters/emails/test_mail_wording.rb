# frozen_string_literal: true

module Emails
  # The admin's test (AdminMailer#test_mail): it says only that mail goes out.
  class TestMailWording < Wording
    # page_url: the admin's page of mail, where the test was sent from.
    def initialize(profile, page_url:)
      super(profile)
      @page_url = page_url
    end

    def subject = I18n.t("emails.test_mail.subject")

    def paragraphs = [ I18n.t("emails.test_mail.body"), I18n.t("emails.test_mail.sent_at", time: I18n.l(Time.current, format: :long)) ]

    def action = Action.new(label: I18n.t("emails.test_mail.action"), url: @page_url)
  end
end
