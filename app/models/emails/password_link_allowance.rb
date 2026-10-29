# frozen_string_literal: true

module Emails
  # How many links to set a password may still be mailed: a few a day to one
  # person, and few an hour and a day for the whole installation, since
  # anyone at the sign-in page can ask for one. Every request counts, sent
  # or not. Asked and spent under one lock (Profiles::RequestPasswordLink).
  #
  #   Emails::PasswordLinkAllowance.new(profile).any_left?
  class PasswordLinkAllowance
    PER_PERSON_A_DAY = 3
    AN_HOUR = 2
    A_DAY = 10

    def initialize(profile, now = Time.current)
      @profile = profile
      @now = now
    end

    def any_left?
      asked_since(1.day).where(profile_id: @profile.id).count < PER_PERSON_A_DAY &&
        asked_since(1.hour).count < AN_HOUR && asked_since(1.day).count < A_DAY
    end

    private

    def asked_since(period) = OutgoingEmail.password_link.where(created_at: (@now - period)..)
  end
end
