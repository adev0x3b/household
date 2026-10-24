# frozen_string_literal: true

# A household's members, from its page (HouseholdsController): removing
# one, with everything they kept (Profiles::Destroy). Who may is
# ProfilePolicy, and the admin types their password first. A link for a
# member to set a password is HouseholdMemberPasswordLinksController's.
class HouseholdMembersController < ApplicationController
  include ReauthenticatesAdmin

  def destroy
    member = policy_scope(Profile).joined.find(params[:id])
    authorize member
    return unless admin_password_given?(subtitle: t("households.password_check.remove", name: member.display_name),
                                        submit: t("households.password_check.remove_submit"), danger: true)

    Profiles::Destroy.call(member)
    roster = Households::Roster.new(member.household, viewer: current_profile)
    render turbo_stream: [ close_modal, turbo_stream.replace(Views::Households::People::ID, Views::Households::People.new(roster: roster)),
                           toast(:success, t("households.notices.removed", name: member.display_name)) ]
  end
end
