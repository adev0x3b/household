# frozen_string_literal: true

module Emails
  module Kinds
    # A link to set a new password, to the confirmed address of someone who
    # forgot theirs (Profiles::RequestPasswordLink). Its token is made as
    # the mail goes, so a link is never kept in the outbox, and works for
    # Profile::SHORT_PASSWORD_LINK_FOR from then. The row keeps when it made
    # its link, never the link, to tell it from one handed over since.
    class PasswordLink < Kind
      def self.key = :password_link

      # Asked for at the door: worth sending soon or not at all.
      def self.waits_at_most = 30.minutes

      # None once the person may no longer have one by mail, or when someone
      # has handed them a link since they asked (the household's owner, the
      # admin, or the server's admin:password_link): the newest link wins.
      # Decided and made on the person's row, locked and read again, so the
      # mail goes to the address the link was made for, and a change of
      # address after it ends the link (Profiles::ConfirmEmail).
      def message
        token = with_profile_locked do
          next unless Profiles::RequestPasswordLink.mailable?(profile) && !handed_one_since?

          profile.short_password_link_token!.tap { row.update_columns(data: { "link_made_at" => link_time }) }
        end
        return unless token

        Outgoing.new(mail: AccountMailer.with(profile: profile, token: token).password_link.message, rows: rows)
      end

      # The link made for this mail stops working, since the mail didn't go
      # out; a link handed over since is left alone.
      def ended
        with_profile_locked { profile.forget_password_link! if made_for_this_mail? }
      end

      private

      # One request is on its way at a time (Profiles::RequestPasswordLink).
      def row = rows.first

      def handed_one_since?
        profile.reset_password_sent_at.present? && profile.reset_password_sent_at > row.created_at && !made_for_this_mail?
      end

      def made_for_this_mail? = link_time.present? && link_time == row.data["link_made_at"]

      # When the person's link was made, to the microsecond and in UTC, so
      # it reads the same whichever zone the drain is in.
      def link_time = profile.reset_password_sent_at&.utc&.iso8601(6)
    end
  end
end
