# frozen_string_literal: true

# Invites someone into a household by email: a Profile with no username and
# no password yet (devise_invitable), which becomes a member when they accept.
# The only way a profile comes to exist, apart from seeds.
#
#   result = Households::Invite.call(household, inviter: current_profile, email: "sam@example.com")
#   result.success?    # false: nothing was saved; result.error and the profile's errors say why
#   result.profile     # the invited Profile
#   result.token       # goes in the accept link, readable only now (the database keeps a digest)
#
# The link is the invitation: the inviter hands it over (copied once from the
# household page). Nothing is emailed: mail is link-only.
#
# Limits (Household): the installation's household size, counting
# invitations not yet accepted, and its invitations per member into their
# own household (Platform) — none where the installation has invitations off
# (Platform.invitations?), unless the inviter runs the app.
# Inviting an address already waiting in this household sends a new link
# (as Households::RenewInvitation does from the list); an address known
# anywhere else is refused the same way whatever it is, so nothing is
# learned about other households.
module Households
  class Invite
    Result = ServiceResult.define(:profile, :token)

    def self.call(household, inviter:, email:, first_name: nil) = new(household, inviter:, email:, first_name:).call

    def initialize(household, inviter:, email:, first_name:)
      @household = household
      @inviter = inviter
      @email = email.to_s.strip.downcase
      @first_name = first_name.to_s.squish.presence
    end

    # The limits are checked and the invitation saved under the household's
    # lock: two invitations sent together can't both take the last place.
    def call
      return refused(Profile.new(household: @household, email: @email), :base, :invitations_off) unless @inviter.admin? || Platform.invitations?

      @household.with_lock do
        waiting = @household.invitations.find_by(email: @email)
        next save_invitation(waiting) if waiting

        profile = Profile.new(household: @household, email: @email, first_name: @first_name)
        next refused(profile, :base, :household_full, max: Platform.household_size) if @household.full?
        next refused(profile, :base, :no_invites_left, max: Platform.invitations_per_member) if @household.invites_left_for(@inviter)&.zero?
        next refused(profile, :email, :invalid) unless @email.match?(Devise.email_regexp)
        next refused(profile, :email, :taken) if Profile.exists?(email: @email)

        save_invitation(profile)
      end
    end

    private

    def refused(profile, attribute, error, **options)
      profile.errors.add(attribute, error, **options)
      Result.new(profile: profile, token: nil, error: error)
    end

    def save_invitation(profile) = Result.new(profile: profile, token: profile.issue_invitation!(@inviter), error: nil)
  end
end
