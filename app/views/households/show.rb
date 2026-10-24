# frozen_string_literal: true

# A household's page: its name, then its people (Views::Households::People).
# The members' own (/household) and the admin's (/admin/households/:id,
# with the way back to the list). Inviting is the top bar's.
class Views::Households::Show < Views::Base
  # roster: the household's people as the viewer sees them (Households::Roster).
  def initialize(roster:, fresh: nil, back_href: nil)
    @roster = roster
    @household = roster.household
    @viewer = roster.viewer
    @fresh = fresh
    @back_href = back_href
  end

  def page_title = @household.name

  # Inviting, gone when the viewer can add nobody: not theirs to do, their
  # invitations spent, or the household full.
  def navbar_controls
    return unless Pundit.policy!(@viewer, @household).invite? && @roster.room_to_invite?

    invite = Components::Action.new(href: routes.new_household_invitation_path(@household), icon: "fa-user-plus",
                                    label: t("households.invite.title"), turbo_stream: true)
    Components::PageControls.new(actions: [ invite ])
  end

  def view_template
    div(class: "report-page household") do
      render Components::PageHeader.new(title: @household.name, back_href: @back_href, back_label: t("admin.households.index.title"))
      render Views::Households::People.new(roster: @roster, fresh: @fresh)
    end
  end
end
