# frozen_string_literal: true

# A link for someone who has an account to set a password: for a member who
# never got one (a seeded account), or who lost theirs. There is no
# "forgot your password" email: the household's owner or the admin makes
# this on the household page and hands it over. It lasts Devise's
# reset_password_within, any earlier one stops working, and setting the
# password opens an account locked by wrong passwords.
#
# The person is told, on every device they turned notifications on for:
# whoever opens the link becomes them, so a link they didn't ask for is
# theirs to stop while it is still unused.
#
#   result = Profiles::PasswordLink.call(profile, by: current_profile)
#   result.token   # goes in edit_profile_password_url(reset_password_token:), readable only now
module Profiles
  class PasswordLink
    Result = Data.define(:profile, :token)

    def self.call(profile, by:)
      raise ArgumentError, "#{profile.email} hasn't accepted their invitation" if profile.invitation_pending?

      token = profile.password_link_token!
      Notifications::Deliver.call(recipient: profile, kind: :password_link_made, actor: by)
      Result.new(profile: profile, token: token)
    end
  end
end
