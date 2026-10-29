# frozen_string_literal: true

# Every mail the app sends (Emails): from the relay's sender under the app's
# name, to one bare address, in two parts drawn from one wording
# (app/presenters/emails): plain text, and HTML drawn by
# Views::Emails::Message. Only a kind of mail makes one (Emails::Kinds),
# in its person's language and zone, and only Emails::Relay sends it.
class ApplicationMailer < ActionMailer::Base
  private

  # Every mail is the app's own, which nobody reads replies to: marked so,
  # an out-of-office answer isn't sent back to it (RFC 3834). A mail goes
  # to one mailbox: an address that isn't one is refused here, rather than
  # mailed to everyone it lists. So is one Mail would send somewhere else,
  # as it decodes an encoded word ("=?utf-8?q?…?=") in an address before
  # handing it to the relay.
  def compose(to:, wording:, headers: {})
    raise ArgumentError, "a mail goes to one address" unless to.to_s.match?(URI::MailTo::EMAIL_REGEXP)

    message = mail(to: to, from: sender, subject: wording.subject, "Auto-Submitted" => "auto-generated", **headers) do |format|
      format.text { render plain: wording.text }
      format.html { render Views::Emails::Message.new(wording) }
    end
    raise ArgumentError, "a mail goes to the address it was made for" unless message.smtp_envelope_to == [ to ]
  end

  # A display name a person typed never goes in a header: it could hold an
  # address of its own. The sender's is the app's.
  def sender = email_address_with_name(Emails::RelaySettings.current.from, I18n.t("app.name"))
end
