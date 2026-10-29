# frozen_string_literal: true

module Profiles
  # Mails the link that confirms an address again, from the Account page: to
  # the new address waiting, else to the one in use while it isn't
  # confirmed, within a few a day (Emails::ConfirmationAllowance), counted
  # under the household's lock so two presses at once can't both take the
  # last.
  #
  #   result = Profiles::SendEmailConfirmation.call(current_profile)
  #   result.error   # :mail_off, :nothing_to_confirm, :no_links_left
  class SendEmailConfirmation
    Result = ServiceResult.define(:profile)

    def self.call(profile)
      return Result.new(profile:, error: :mail_off) unless Emails.enabled?
      return Result.new(profile:, error: :nothing_to_confirm) if profile.email_confirmed? && profile.unconfirmed_email.nil?

      profile.household.with_lock do
        next Result.new(profile:, error: :no_links_left) unless Emails::ConfirmationAllowance.new(profile).any_left?

        Emails::Enqueue.call(profile, :email_confirmation)
        Result.new(profile:, error: nil)
      end
    end
  end
end
