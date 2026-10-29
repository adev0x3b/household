# frozen_string_literal: true

# A mail to one person in the outbox (Emails): its kind (Emails::Kinds),
# from when it may go and until when it is worth sending, and how it
# ended. It keeps ids, dates and times, never words, which are made as it
# goes, in the person's language; an address only for a notice that must
# reach the one the person had when it was queued, cleared once the row
# ends. Queued by
# Emails::Enqueue, sent by Emails::Drain, which claims a row (sending)
# before it speaks to the relay, so two drains never send one twice.
# held_for_settings_at: when the relay refused it in words that may have
# been about this copy's settings or about this mail, which the mail sent
# since then decides (Emails::Drain).
class OutgoingEmail < ApplicationRecord
  belongs_to :profile

  enum :kind, { password_link: 0, password_changed: 1, email_change_requested: 2, email_changed: 3, email_confirmation: 4, test_mail: 5,
                reminder: 6 }, validate: true
  enum :status, { queued: 0, sending: 1, sent: 2, failed: 3, dropped: 4 }
  # Why it waits, or why it failed: the admin's page words each. One that
  # waited past its time keeps what kept it waiting, if anything did.
  enum :reason, { over_budget: 0, drain_stopped: 1, unavailable: 2, misconfigured: 3, held: 4, refused: 5, not_made: 6, unexpected: 7,
                  expired: 8 }, prefix: true

  validates :not_before, :expires_at, presence: true

  # Waiting, and may go now.
  scope :due, ->(now) { queued.where(not_before: ..now) }

  # Taken to go since then: a message counted against a budget, whether it
  # is still on its way, gone or refused. A refusal counts, so a relay that
  # refuses everything fails no more than the budget in an hour.
  scope :claimed_since, ->(time) { where(status: %i[sending sent failed], claimed_at: time..) }

  # How many messages these rows went out in: reminders due together share one.
  def self.messages = distinct.count(:message_id)

  def self.for_household(household) = where(profile_id: Profile.where(household_id: household.id).select(:id))

  # A person's reminders that couldn't be mailed in the last day, for their account page.
  def self.reminders_not_mailed(profile, now: Time.current) = reminder.failed.where(profile_id: profile.id, updated_at: (now - 1.day)..).count

  # Whether a person's link to confirm an address is still to go out, for
  # their account page: the link of a try that waits may be in place, but
  # it went nowhere.
  def self.confirmation_on_its_way?(profile) = email_confirmation.where(profile_id: profile.id, status: %i[queued sending]).exists?
end
