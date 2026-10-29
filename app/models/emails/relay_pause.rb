# frozen_string_literal: true

module Emails
  # The relay refused this copy's own settings (Emails::Relay::Misconfigured):
  # nothing is sent for a while, since every message would be refused alike
  # until the admin fixes them, and the admin's page of mail says what to
  # fix. Kept in the cache, which every process shares. A test mail starts
  # sending again at once (Admin::TestMailsController).
  #
  #   Emails::RelayPause.start(error)
  #   Emails::RelayPause.current   # => an Emails::RelayPause (problem, reply, ends_at), or nil
  class RelayPause
    KEY = "emails/relay_pause"
    LENGTH = 15.minutes

    attr_reader :problem, :reply, :ends_at

    # error: the Emails::Relay::Misconfigured that stopped the mail.
    def self.start(error, now: Time.current)
      Rails.cache.write(KEY, { "problem" => error.problem.to_s, "reply" => Emails.without_addresses(error.reply).squish.presence,
                               "ends_at" => (now + LENGTH).iso8601 }, expires_in: LENGTH)
    end

    def self.current
      stored = Rails.cache.read(KEY) or return
      new(problem: stored["problem"].to_sym, reply: stored["reply"], ends_at: Time.zone.parse(stored["ends_at"]))
    end

    def self.clear = Rails.cache.delete(KEY)

    # problem: one of Emails::Relay::MISCONFIGURED's keys; reply: what the
    # relay answered, its addresses masked, if it answered.
    def initialize(problem:, reply:, ends_at:)
      @problem = problem
      @reply = reply
      @ends_at = ends_at
    end
  end
end
