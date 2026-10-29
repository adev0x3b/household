# frozen_string_literal: true

module Emails
  # What the installation may still mail in the rolling hour and day
  # (Platform.mails_per_hour, Platform.mails_per_day), every kind and
  # household together, counted in messages taken to go. Mail that isn't
  # about an account (reminders, the admin's tests) leaves the last of each
  # hour and the last five of each day to the mail that is, so a busy
  # morning of reminders never keeps a link to set a password from going out.
  #
  #   Emails::RelayAllowance.new.allows?(Emails::Kinds::TestMail)
  class RelayAllowance
    KEPT_FOR_ACCOUNT_MAIL_EACH_HOUR = 1
    KEPT_FOR_ACCOUNT_MAIL_EACH_DAY = 5

    def initialize(now = Time.current)
      @now = now
    end

    def left_this_hour = Platform.mails_per_hour - taken_since(@now - 1.hour)

    def left_today = Platform.mails_per_day - taken_since(@now - 1.day)

    def allows?(kind)
      return left_this_hour.positive? && left_today.positive? if kind.account?

      left_this_hour > KEPT_FOR_ACCOUNT_MAIL_EACH_HOUR && left_today > KEPT_FOR_ACCOUNT_MAIL_EACH_DAY
    end

    private

    def taken_since(time) = OutgoingEmail.claimed_since(time).messages
  end
end
