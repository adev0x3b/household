# frozen_string_literal: true

# /household — the current profile's household: who is in it, who has been
# invited, and inviting someone (HouseholdInvitationsController).
# /admin/households/:id is the same page for the admin.
class HouseholdsController < ApplicationController
  def show
    household = current_profile.household
    authorize household

    render_page Views::Households::Show.new(roster: Households::Roster.new(household, viewer: current_profile))
  end
end
