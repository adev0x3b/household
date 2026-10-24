# frozen_string_literal: true

# /admin/households — every household of the app, for whoever runs it:
#   index          the list, with how full each one is
#   new / create   a household and its first member's invitation (Households::Create)
#   show           one household's people and invitations (the members' own page)
class Admin::HouseholdsController < Admin::BaseController
  PER_PAGE = 50

  def index
    render_page Views::Admin::Households::Index.new(households: Household.order(:name, :id).includes(:profiles).paginate(page: params[:page], per_page: PER_PAGE))
  end

  def show
    household = Household.find(params[:id])
    authorize household

    render_page Views::Households::Show.new(roster: Households::Roster.new(household, viewer: current_profile), fresh: fresh_invitation(household),
                                            back_href: admin_households_path)
  end

  def new
    render_modal(Views::Admin::Households::Modals::New.new(household: Household.new), page: admin_households_path)
  end

  # On success its page opens, with the first member's link to copy.
  def create
    given = params.expect(household: %i[name first_member_email first_member_first_name])
    result = Households::Create.call(name: given[:name], email: given[:first_member_email],
                                     first_name: given[:first_member_first_name], inviter: current_profile)
    if result.success?
      session[:fresh_invitation] = { "id" => result.invitation.profile.id, "token" => result.invitation.token }
      redirect_to admin_household_path(result.household), status: :see_other
    else
      render turbo_stream: redraw_modal(Views::Admin::Households::Modals::New.new(household: result.household)), status: :unprocessable_content
    end
  end

  private

  # The invitation just made by #create, carried over the redirect and read once.
  def fresh_invitation(household)
    fresh = session.delete(:fresh_invitation)
    return if fresh.nil?

    profile = household.invitations.find_by(id: fresh["id"])
    return if profile.nil?

    Households::Invite::Result.new(profile: profile, token: fresh["token"], error: nil)
  end
end
