# frozen_string_literal: true

# Invitations into a household, from its page (HouseholdsController, and
# the admin's Admin::HouseholdsController): made under the household
# (Households::Invite), and taken back by its inviter or the household's
# owner (Households::CancelInvitation). A new link for one still waiting is
# HouseholdInvitationRenewalsController's. Who may invite is
# HouseholdPolicy#invite?; who may cancel is ProfilePolicy. Accepting one is
# Profiles::InvitationsController; removing a member is
# HouseholdMembersController. Every response redraws the page's people.
class HouseholdInvitationsController < ApplicationController
  before_action :set_household, only: %i[new create]
  before_action(only: %i[new create]) { authorize @household, :invite? }

  def new
    render_modal(form(Profile.new(household: @household)), page: household_page)
  end

  def create
    given = params.expect(profile: %i[email first_name])
    result = Households::Invite.call(@household, inviter: current_profile, email: given[:email], first_name: given[:first_name])

    if result.success?
      render turbo_stream: [ close_modal, people(result), toast(:success, t("households.notices.invited", email: result.profile.email)) ]
    else
      render turbo_stream: redraw_modal(form(result.profile)), status: :unprocessable_content
    end
  end

  def destroy
    invitation = policy_scope(Profile).invitation_pending.find(params[:id])
    authorize invitation, :cancel_invitation?
    @household = invitation.household

    Households::CancelInvitation.call(invitation)
    render turbo_stream: [ people, toast(:success, t("households.notices.cancelled", email: invitation.email)) ]
  end

  private

  def set_household
    @household = policy_scope(Household).find(params[:household_id])
  end

  def form(profile) = Views::HouseholdInvitations::Modals::New.new(profile: profile)

  # A member invites from their own household's page; the admin, from the
  # household's page among their tools.
  def household_page = @household == current_profile.household ? household_path : admin_household_path(@household)

  def people(result = nil)
    roster = Households::Roster.new(@household, viewer: current_profile)
    turbo_stream.replace(Views::Households::People::ID, Views::Households::People.new(roster: roster, fresh: result))
  end
end
