# frozen_string_literal: true

module Profiles
  # Confirms the address a link was mailed to, from the link's page and in a
  # session signed in as its person (Accounts::EmailConfirmation): a new
  # address takes over, else the one in use is confirmed. The link works
  # once, and an address confirmed before that stops being theirs hears of
  # it. A person who never picked a language gets the page's, so the mail
  # that follows arrives in it.
  #
  #   result = Profiles::ConfirmEmail.call(current_profile, token: params[:token])
  #   result.error   # :expired (no such link, or out of date), :not_yours, :taken (someone else has the address now)
  class ConfirmEmail
    Result = ServiceResult.define(:profile)

    # Decided and saved on the person's row, locked and read again, so a
    # link to set a password made for the old address meanwhile
    # (Emails::Kinds::PasswordLink) ends with it.
    def self.call(profile, token:, locale: I18n.locale, now: Time.current)
      profile.with_lock do
        problem = problem(profile, token:, now:)
        next Result.new(profile:, error: problem) if problem

        address = profile.address_to_confirm
        previous = profile.email if profile.email_confirmed? && address != profile.email
        profile.update!(email: address, unconfirmed_email: nil, email_confirmed_at: now, locale: profile.locale.presence || locale.to_s,
                        email_confirmation_digest: nil, email_confirmation_sent_at: nil, email_confirmation_address_digest: nil)
        Emails::Enqueue.call(profile, :email_changed, data: { "to" => previous }) if previous
        Result.new(profile:, error: nil)
      end
    end

    # Why the link can't confirm anything for this person, or nil when it
    # can: what its page says before the press, and the press refuses with.
    def self.problem(profile, token:, now: Time.current)
      owner = Profile.with_email_confirmation_token(token, now:)
      return :expired if owner.nil?
      return :not_yours if owner != profile

      :taken if Profile.where.not(id: profile.id).exists?(email: profile.address_to_confirm)
    end
  end
end
