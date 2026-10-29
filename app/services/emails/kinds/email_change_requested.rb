# frozen_string_literal: true

module Emails
  module Kinds
    # To the confirmed address, when someone asks for another one to take
    # over: the person hears of it there before it can happen.
    class EmailChangeRequested < Kind
      def self.key = :email_change_requested

      def self.waits_at_most = 1.day

      def message
        Outgoing.new(mail: AccountMailer.with(profile: profile, to: rows.first.data.fetch("to"), at: rows.first.created_at).email_change_requested.message, rows: rows)
      end
    end
  end
end
