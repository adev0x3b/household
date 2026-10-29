# frozen_string_literal: true

module Emails
  # The admin's page of mail (/admin/emails): whether mail goes out, and
  # what stops it otherwise; what went in the rolling hour and day against
  # the installation's budgets; what waits; and what couldn't go out
  # lately, whose it was and what the relay answered. A row keeps no words
  # of a mail, so neither does the page. Each is read once.
  #
  #   overview = Emails::Overview.new
  #   overview.state     # => :off, :unconfigured, :paused or :sending
  #   overview.waiting   # => the next rows to go, soonest first
  #   overview.failed    # => the latest that couldn't go out, newest first
  class Overview
    # How many rows each list shows; the counts are of them all.
    LISTED = 20
    # As far back as a failed row is kept (Emails::SweepJob).
    FAILED_SINCE = 30.days

    attr_reader :relay, :pause

    def initialize(now: Time.current)
      @now = now
      @relay = RelaySettings.current
      @pause = RelayPause.current
    end

    def state
      if !Platform.outgoing_mail? then :off
      elsif !relay.configured? then :unconfigured
      elsif pause then :paused
      else :sending
      end
    end

    # Whether mail can go, now or once the pause ends (Emails.enabled?).
    def enabled? = %i[sending paused].include?(state)

    # Messages taken to go, on their way, gone or refused: what the budgets count.
    def used_this_hour = (@used_this_hour ||= OutgoingEmail.claimed_since(@now - 1.hour).messages)
    def used_today = (@used_today ||= OutgoingEmail.claimed_since(@now - 1.day).messages)

    def hourly_budget = Platform.mails_per_hour
    def daily_budget = Platform.mails_per_day

    def waiting = (@waiting ||= listed(unsent.order(:not_before, :id)))
    def waiting_count = (@waiting_count ||= unsent.count)

    def failed = (@failed ||= listed(failed_lately.order(updated_at: :desc, id: :desc)))
    def failed_count = (@failed_count ||= failed_lately.count)

    private

    def unsent = OutgoingEmail.where(status: %i[queued sending])

    def failed_lately = OutgoingEmail.failed.where(updated_at: (@now - FAILED_SINCE)..)

    def listed(rows) = rows.includes(profile: :household).limit(LISTED).to_a
  end
end
