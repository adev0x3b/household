# frozen_string_literal: true

module Emails
  # How many links to confirm an address a person may still ask for: a few
  # a day, counted in the outbox, so nobody can have the app mail an
  # address over and over, theirs or not. Asked and spent under the
  # household's lock (Accounts::EmailChange, Profiles::SendEmailConfirmation).
  #
  #   Emails::ConfirmationAllowance.new(profile).any_left?
  class ConfirmationAllowance
    PER_DAY = 3

    def initialize(profile, now = Time.current)
      @profile = profile
      @now = now
    end

    def any_left? = OutgoingEmail.email_confirmation.where(profile_id: @profile.id, created_at: (@now - 1.day)..).count < PER_DAY
  end
end
