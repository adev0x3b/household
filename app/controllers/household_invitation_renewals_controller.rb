# frozen_string_literal: true

# A new link for an invitation still waiting, made by its inviter or the
# admin (Households::RenewInvitation) and shown once, right there, to
# copy. Only an invitation still waiting: a member is never reached from here.
class HouseholdInvitationRenewalsController < ApplicationController
  def create
    invitation = policy_scope(Profile).invitation_pending.find(params[:household_invitation_id])
    authorize invitation, :renew_invitation?

    result = Households::RenewInvitation.call(invitation, by: current_profile)
    roster = Households::Roster.new(invitation.household, viewer: current_profile)
    render turbo_stream: [ turbo_stream.replace(Views::Households::People::ID, Views::Households::People.new(roster: roster, fresh: result)),
                           toast(:success, t("households.notices.invited", email: result.profile.email)) ]
  end
end
