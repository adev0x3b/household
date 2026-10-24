# frozen_string_literal: true

# A link for a member to set a password (a seeded account, a lost one),
# made by the admin or the household's owner (Profiles::PasswordLink)
# and shown once, right there, to hand over. The admin types their
# password first: the link is the account.
class HouseholdMemberPasswordLinksController < ApplicationController
  include ReauthenticatesAdmin

  def create
    member = policy_scope(Profile).joined.find(params[:household_member_id])
    authorize member, :password_link?
    return unless admin_password_given?(subtitle: t("households.password_check.password_link", name: member.display_name),
                                        submit: t("households.password_check.password_link_submit"))

    result = Profiles::PasswordLink.call(member, by: current_profile)
    roster = Households::Roster.new(member.household, viewer: current_profile)
    render turbo_stream: [ close_modal, turbo_stream.replace(Views::Households::People::ID, Views::Households::People.new(roster: roster, fresh: result)),
                           toast(:success, t("households.notices.password_link", name: member.display_name)) ]
  end
end
