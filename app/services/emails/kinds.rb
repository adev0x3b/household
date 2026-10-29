# frozen_string_literal: true

module Emails
  # Every kind of mail, in the order a drain sends what is due when the
  # budget is short: a link someone waits for at the door first, the
  # reminders last. Adding one is a class here and its OutgoingEmail kind.
  module Kinds
    def self.all = [ PasswordLink, PasswordChanged, EmailChangeRequested, EmailChanged, EmailConfirmation, TestMail, Reminder ]

    def self.for(key) = find(key) || raise(ArgumentError, "no kind of mail #{key}")

    # The kind, or nil for a row this version has no class for (queued by a
    # newer one before a rollback), which a drain never sends.
    def self.find(key) = all.find { _1.key.to_s == key.to_s }
  end
end
