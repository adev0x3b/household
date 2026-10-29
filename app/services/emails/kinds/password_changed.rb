# frozen_string_literal: true

module Emails
  module Kinds
    # To the address confirmed when the password changed, whichever way it
    # changed, and even once another address has taken over: whoever
    # changed both can't keep it from hearing of the first.
    class PasswordChanged < Kind
      def self.key = :password_changed

      def self.waits_at_most = 1.day

      # Notices still waiting for one address go as one, telling of the
      # first change, so a password changed over and over while the
      # household's share is spent costs one mail when there is room again.
      def self.batch(row)
        OutgoingEmail.queued.where(profile_id: row.profile_id, kind: key).select { _1.data["to"] == row.data["to"] }
      end

      def message
        Outgoing.new(mail: AccountMailer.with(profile: profile, to: rows.first.data.fetch("to"), at: rows.first.created_at).password_changed.message,
                     rows: rows)
      end
    end
  end
end
