# frozen_string_literal: true

module Profiles
  # Someone at the sign-in page forgot their password and typed their
  # username or address (Profiles::PasswordLinkRequestJob). A link goes to
  # their confirmed address (Emails::Kinds::PasswordLink) when they may have
  # one by mail, have none on its way or still working, and are within the
  # limits (Emails::PasswordLinkAllowance). Nothing tells the asker which.
  #
  #   Profiles::RequestPasswordLink.call(profile)   # true when a link was queued
  class RequestPasswordLink
    # Every request is decided under one lock for the installation, whose
    # limits they share, so two at once can't both take the last place.
    LOCK = 0x50617373 # "Pass"

    def self.call(profile, now: Time.current)
      return false unless Emails.enabled? && mailable?(profile)

      Profile.transaction do
        Profile.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK})")
        next false if open?(profile.reload, now) || !Emails::PasswordLinkAllowance.new(profile, now).any_left?

        Emails::Enqueue.call(profile, :password_link, now: now)
        true
      end
    end

    # Who may have a link by mail: someone who has joined, at an address
    # they confirmed. Never the admin, whose way back is the server
    # (admin:password_link), nor an open account, whose door needs no password.
    def self.mailable?(profile)
      !profile.invitation_pending? && !profile.admin? && !Platform.open_account?(profile) && profile.email_confirmed?
    end

    # One at a time: a link on its way, or out and still working.
    def self.open?(profile, now)
      OutgoingEmail.password_link.where(profile_id: profile.id, status: %i[queued sending]).exists? || profile.short_password_link_open?(now)
    end
    private_class_method :open?
  end
end
