# frozen_string_literal: true

# The mail the app sends: the reminders a person asked for by email, a link
# to set a password, the confirmation of an address, the notices about an
# account. Every mail goes through the outbox (OutgoingEmail, by
# Emails::Enqueue) and out through the relay the admin set
# (Emails::RelaySettings), within the installation's budgets (Platform).
# Mail goes out only where the admin left it on (Platform.outgoing_mail?)
# and a relay is set: staging, dev and the demo send none.
module Emails
  ADDRESS = /[^\s<>()]+@[^\s<>()]+/

  def self.enabled? = Platform.outgoing_mail? && RelaySettings.current.configured?

  # Whether mail can reach this person: mail goes out, and their address is
  # confirmed. Only the link that confirms it goes to an address not yet confirmed.
  def self.available_to?(profile) = profile.email_confirmed? && enabled?

  # Whether a person's reminders may come by email too, for their reminder
  # form and for Reminders::DispatchJob: :available; :unconfirmed, while
  # mail goes out but not yet to them (their account page confirms the
  # address); or :off. Never for an open account, whose address is nobody's
  # who uses it, nor where the admin allows households no reminder mail.
  def self.for_reminders(profile)
    return :off if !enabled? || Platform.open_account?(profile) || Platform.reminder_mails_per_day.zero?

    profile.email_confirmed? ? :available : :unconfirmed
  end

  # What a relay answered, as it is kept: an address in it may be a person's.
  def self.without_addresses(text) = text.to_s.gsub(ADDRESS, "[address]")
end
