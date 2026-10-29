# frozen_string_literal: true

# The reminders a person asked for by email (Emails::Kinds::Reminder): one
# mail for those that fell due together, to their confirmed address. Its
# foot and its List-Unsubscribe header, which a mail client may press in
# one click (RFC 8058), carry the link that stops them all
# (EmailUnsubscriptionsController).
class RemindersMailer < ApplicationMailer
  # reminders: Reminders::StillDue's, soonest due first.
  def reminders
    profile = params.fetch(:profile)
    reminders = params.fetch(:reminders)
    stop_url = email_unsubscription_url(token: profile.generate_token_for(:email_unsubscription))
    wording = Emails::RemindersWording.new(profile, reminders: reminders, calendar_url: calendar_url_at(reminders.first.occurrence.date),
                                                    unsubscribe_url: stop_url)
    compose(to: profile.email, wording: wording,
            headers: { "List-Unsubscribe" => "<#{stop_url}>", "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click" })
  end

  private

  # The calendar's month at the day, where the bell's reminder leads too.
  def calendar_url_at(date) = calendar_url(month: date.month, year: date.year, anchor: "day_#{date.iso8601}")
end
