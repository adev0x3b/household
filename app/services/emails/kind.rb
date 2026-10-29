# frozen_string_literal: true

module Emails
  # A kind of mail (Emails::Kinds.all): what its rows are for and how its
  # message is made. Every kind answers, on the class:
  #
  #   key             its OutgoingEmail kind
  #   waits_at_most   how long a queued row is still worth sending
  #   account?        mail about a person's account, which may use the whole
  #                   of the installation's budget; other mail leaves it the
  #                   last of each hour and day (Emails::RelayAllowance)
  #   room_in?(household, now)
  #                   whether the household's own budget lets one more go
  #                   now: for account mail, its share of the installation's
  #                   (Emails::AccountMailAllowance)
  #   sends_at_once?  a drain starts as soon as a row is queued, rather than
  #                   at the next minute's
  #   batch(row)      the rows that go out in one message with it
  #
  # and, on an instance made from the rows a drain claimed:
  #
  #   message         the mail and the rows it carries (Emails::Outgoing), or
  #                   nil when none is still wanted; rows it leaves out are dropped
  #   ended           the rows end unsent, failed or dropped: undo what
  #                   making their message did (a link minted for it)
  class Kind
    def self.account? = true

    def self.room_in?(household, now) = AccountMailAllowance.new(household, now).any_left?

    def self.sends_at_once? = true

    def self.batch(row) = [ row ]

    # rows: one person's rows of this kind, claimed by a drain or ending unsent.
    def initialize(rows)
      @rows = rows
      @profile = rows.first.profile
    end

    def ended; end

    private

    attr_reader :rows, :profile

    # The person's row, locked and read again, for the block; nothing once
    # they are gone, their mail with them (Profiles::Destroy).
    def with_profile_locked(&)
      profile.with_lock(&)
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
