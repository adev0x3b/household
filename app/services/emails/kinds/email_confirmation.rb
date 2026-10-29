# frozen_string_literal: true

module Emails
  module Kinds
    # The link that confirms an address, to that address: a new one waiting
    # to take over, else the one in use (Profile#address_to_confirm). The
    # token is made as the mail goes, so a link is never kept in the
    # outbox, and asking twice before it went sends one mail. The rows keep
    # when they made their link, never the link.
    class EmailConfirmation < Kind
      def self.key = :email_confirmation

      def self.waits_at_most = 1.hour

      def self.batch(row) = OutgoingEmail.queued.where(profile_id: row.profile_id, kind: key).to_a

      # None once the address is confirmed and no other waits. Decided and
      # made on the person's row, locked and read again, so an address
      # confirmed meanwhile (Profiles::ConfirmEmail) gets no link after it.
      def message
        token = with_profile_locked do
          next if profile.email_confirmed? && profile.unconfirmed_email.nil?

          profile.email_confirmation_token!.tap { rows.each { _1.update_columns(data: { "link_made_at" => link_time }) } }
        end
        return unless token

        mail = AccountMailer.with(profile: profile, to: profile.address_to_confirm, token: token).email_confirmation.message
        Outgoing.new(mail: mail, rows: rows)
      end

      # The link made for this mail stops working, since the mail didn't go
      # out: the account page offers to mail one again, rather than say one went.
      def ended
        with_profile_locked { profile.forget_email_confirmation_link! if made_for_this_mail? }
      end

      private

      def made_for_this_mail? = link_time.present? && rows.any? { _1.data["link_made_at"] == link_time }

      # When the person's link was made, to the microsecond and in UTC, so
      # it reads the same whichever zone the drain is in.
      def link_time = profile.email_confirmation_sent_at&.utc&.iso8601(6)
    end
  end
end
