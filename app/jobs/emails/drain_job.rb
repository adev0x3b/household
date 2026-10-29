# frozen_string_literal: true

module Emails
  # Sends what is due in the outbox (Emails::Drain): every minute
  # (config/recurring.yml), and as soon as account mail is queued
  # (Emails::Enqueue). One at a time: a drain that finds another running
  # leaves it the work, and the next minute's takes over whatever it left.
  class DrainJob < ApplicationJob
    limits_concurrency to: 1, key: "emails", duration: 15.minutes, on_conflict: :discard
    runs_outside_web_server

    def perform = Drain.call
  end
end
