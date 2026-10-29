# frozen_string_literal: true

module Emails
  module Kinds
    # To the address that was confirmed before, once a new one took over.
    class EmailChanged < Kind
      def self.key = :email_changed

      def self.waits_at_most = 1.day

      def message
        Outgoing.new(mail: AccountMailer.with(profile: profile, to: rows.first.data.fetch("to"), at: rows.first.created_at).email_changed.message, rows: rows)
      end
    end
  end
end
