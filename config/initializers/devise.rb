# frozen_string_literal: true

# Devise on Profile (its modules are listed there). Only what differs from
# Devise's defaults is set here, each with its reason.
Devise.setup do |config|
  require "devise/orm/active_record"

  # One field takes a username or an email (Profile.find_for_database_authentication).
  config.authentication_keys = [ :login ]
  config.case_insensitive_keys = [ :login ]
  config.strip_whitespace_keys = [ :login ]

  # A refused sign-in never says whether the account exists or is locked.
  config.paranoid = true

  # An address is one mailbox. Devise's own pattern lets a list through
  # ("someone@example.com,another"), and mail to it would reach every name
  # in it, links to set a password too.
  config.email_regexp = URI::MailTo::EMAIL_REGEXP

  # Long over clever (NIST SP 800-63B): at least 12 characters, no rules on
  # what they are. bcrypt at Devise's cost, the cheapest in tests.
  config.password_length = 12..128
  config.stretches = Rails.env.test? ? 1 : 12

  # Ten wrong passwords in a row and the account waits a quarter of an hour
  # (the sign-in's rate limit slows a single address; this, many). Unlocking
  # is by time, or by setting a password from a link (Profiles::PasswordsController),
  # never by Devise's unlock mail. The demo's shared accounts never lock (Profile#lock_access!).
  config.maximum_attempts = 10
  config.unlock_strategy = :time
  config.unlock_in = 15.minutes

  # Twelve idle hours end a session, unless "Remember me" was ticked: two
  # weeks, renewed while in use — the choice on one's own phone.
  config.timeout_in = 12.hours
  config.extend_remember_period = true
  # The remember-me cookie, like the session's, goes to the app's own path only.
  config.rememberable_options = { path: Rails.configuration.x.cookie_path }

  # A password link (Profiles::PasswordLink) is good for two days, an
  # invitation for two weeks.
  config.reset_password_within = 2.days
  config.invite_for = 2.weeks

  # Turbo's statuses: an invalid form re-renders as 422, a redirect after a
  # form is a 303.
  config.responder.error_status = :unprocessable_content
  config.responder.redirect_status = :see_other
end
