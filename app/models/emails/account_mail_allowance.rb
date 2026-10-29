# frozen_string_literal: true

module Emails
  # Whether a household's people may have one more mail about their
  # accounts now: what was taken to go to them in the rolling hour and day,
  # every person's together, against half of each of the installation's
  # budgets, so one household asking for links over and over never keeps
  # another's from theirs. Asked under the household's lock, where the
  # drain claims the mail (Emails::Drain).
  #
  #   Emails::AccountMailAllowance.new(household).any_left?
  class AccountMailAllowance
    def initialize(household, now = Time.current)
      @household = household
      @now = now
    end

    def any_left? = taken_since(1.hour) < half(Platform.mails_per_hour) && taken_since(1.day) < half(Platform.mails_per_day)

    private

    def taken_since(period) = account_mail.claimed_since(@now - period).messages

    def account_mail = OutgoingEmail.where(kind: Kinds.all.select(&:account?).map(&:key)).for_household(@household)

    # Rounded up, so an odd budget leaves the household the larger half.
    def half(budget) = budget.fdiv(2).ceil
  end
end
