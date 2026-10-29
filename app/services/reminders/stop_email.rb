# frozen_string_literal: true

module Reminders
  # Every one of a person's reminders stops coming by email, from the link
  # in a reminder mail (EmailUnsubscriptionsController). A mail already
  # queued is dropped at its turn, since it goes only for a reminder that
  # still asks for email (Reminders::StillDue). Their bell says so, in case
  # it was pressed by whoever they forwarded the mail to.
  #
  #   Reminders::StopEmail.call(profile)   # => how many reminders stopped
  class StopEmail
    def self.call(profile)
      EventReminder.transaction do
        stopped = EventReminder.where(profile_id: profile.id, by_email: true).update_all(by_email: false, updated_at: Time.current)
        Notifications::Deliver.call(recipient: profile, kind: :reminder_mails_stopped) if stopped.positive?
        stopped
      end
    end
  end
end
