# frozen_string_literal: true

module Emails
  # Whether a household's people may have one more reminder mail now: the
  # mails taken to go to them in the rolling day, every person's together,
  # against Platform.reminder_mails_per_day, so one household's reminders
  # never spend the whole installation's budget. Asked under the
  # household's lock, where the drain claims the mail (Emails::Drain).
  #
  #   Emails::ReminderAllowance.new(household).any_left?
  class ReminderAllowance
    def initialize(household, now = Time.current)
      @household = household
      @now = now
    end

    def any_left? = OutgoingEmail.reminder.for_household(@household).claimed_since(@now - 1.day).messages < Platform.reminder_mails_per_day
  end
end
