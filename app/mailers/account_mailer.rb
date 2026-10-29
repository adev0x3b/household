# frozen_string_literal: true

# Mail about a person's account: the link that confirms an address, the
# link to set a forgotten password, and the notices that tell them their
# address or password changed, each to the address it is for (Emails::Kinds).
class AccountMailer < ApplicationMailer
  # To the confirmed address: a link to set a new password.
  def password_link
    url = edit_profile_password_url(reset_password_token: params.fetch(:token))
    compose(to: profile.email, wording: Emails::PasswordLinkWording.new(profile, url: url))
  end

  # The link that confirms `to` as the person's address.
  def email_confirmation
    to = params.fetch(:to)
    compose(to: to, wording: Emails::EmailConfirmationWording.new(profile, address: to, url: account_email_confirmation_url(token: params.fetch(:token))))
  end

  # To the confirmed address: another was asked for.
  def email_change_requested
    compose(to: params.fetch(:to), wording: Emails::EmailChangeRequestedWording.new(profile, at: params.fetch(:at), account_url: account_url))
  end

  # To the address confirmed before: another took over.
  def email_changed
    compose(to: params.fetch(:to), wording: Emails::EmailChangedWording.new(profile, at: params.fetch(:at), account_url: account_url))
  end

  # To the address confirmed when it happened: the password changed.
  def password_changed
    compose(to: params.fetch(:to), wording: Emails::PasswordChangedWording.new(profile, at: params.fetch(:at), account_url: account_url))
  end

  private

  def profile = params.fetch(:profile)
end
