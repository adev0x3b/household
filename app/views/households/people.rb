# frozen_string_literal: true

# Who is in a household and who has been invited, with how many more can
# be: redrawn whole after every invitation (HouseholdInvitationsController)
# and removal (HouseholdMembersController). What the viewer may do to
# someone (ProfilePolicy) sits on that row. `fresh` is the link just made
# — an invitation's (Households::Invite::Result) or a member's to set a
# password (Profiles::PasswordLink::Result): its row shows it, and it
# can't be read again later.
#
# Every button keeps its id from one drawing to the next, so the focus stays
# on it. One whose row leaves hands the focus to a button on the next row,
# else on the one before, else to the whole list.
class Views::Households::People < Views::Base
  ID = "household-people"

  def self.button_id(person, action) = "household-person-#{person.id}-#{action.to_s.dasherize}"

  # roster: the household's people as the viewer sees them (Households::Roster).
  def initialize(roster:, fresh: nil)
    @roster = roster
    @household = roster.household
    @viewer = roster.viewer
    @fresh = fresh
  end

  def view_template
    div(id: ID, class: "household__people", tabindex: "-1") do
      p(class: "report-hint") { room }
      ul(class: "household__list") { @roster.members.each { |member| member_row(member) } }
      invited if @roster.invitations.any?
    end
  end

  private

  # "3 of 20 people. You can invite 4 more.", or "3 people." where the
  # installation sets no limit to count against.
  def room
    plain [ people_count, invitations ].compact.join(" ")
  end

  def people_count
    size = ::Platform.household_size
    return t("households.people.count_unlimited", count: @roster.size) if size.nil?

    t("households.people.count", count: @roster.size, max: size)
  end

  def invitations
    left = @roster.invites_left
    if !Pundit.policy!(@viewer, @household).invite? then t("households.people.invitations_off")
    elsif left.nil? then nil
    elsif left.positive? then t("households.people.invites_left", count: left)
    elsif @household.full? then t("households.people.full")
    else t("households.people.no_invites_left", max: ::Platform.invitations_per_member)
    end
  end

  def member_row(member)
    li(class: "household__row") do
      render Components::Icon.new("fa-user", class: "household__icon")
      div(class: "household__who") do
        p(class: "household__name") do
          plain member.full_name
          span(class: "report-tag") { t("households.people.owner") } if member.id == @household.owner_id
          span(class: "report-tag") { t("households.people.you") } if member == @viewer
        end
      end
      div(class: "household__actions") { member_actions(member) }
      link(member) if @fresh&.profile == member
    end
  end

  def member_actions(member)
    if policy(member).password_link?
      render Components::ItemAction.new(id: button_id(member, :password_link), href: household_member_password_links_path(member), icon: "fa-key",
                                        method: :post, turbo_stream: true,
                                        label: t("households.people.password_link"),
                                        confirm: t("households.people.password_link_confirm", name: member.display_name))
    end
    if policy(member).destroy?
      render Components::ItemAction.new(id: button_id(member, :remove), href: household_member_path(member), icon: "fa-user-minus", method: :delete,
                                        turbo_stream: true, danger: true, data: { focus_fallback: focus_fallback(member) },
                                        label: t("households.people.remove"), confirm: t("households.people.remove_confirm", name: member.display_name))
    end
  end

  def link_url(profile)
    if profile.invitation_pending?
      accept_profile_invitation_url(invitation_token: @fresh.token)
    else
      edit_profile_password_url(reset_password_token: @fresh.token)
    end
  end

  def link_hint(profile)
    if profile.invitation_pending?
      t("households.link.invitation", email: profile.email)
    else
      t("households.link.password", name: profile.display_name, hours: (Devise.reset_password_within / 1.hour).round)
    end
  end

  def policy(profile) = Pundit.policy!(@viewer, profile)
  def button_id(person, action) = self.class.button_id(person, action)

  # For a row that leaves: a button on the next row, else on the one
  # before, else the list. A button the viewer isn't given isn't there, and
  # is passed over.
  def focus_fallback(person)
    people = @roster.members + @roster.invitations
    at = people.index(person)
    [ people[at + 1], (people[at - 1] if at.positive?) ].compact.flat_map { button_ids(_1) }.push(ID).join(" ")
  end

  def button_ids(person) = (person.invitation_pending? ? %i[renew cancel] : %i[password_link remove]).map { button_id(person, _1) }

  def invited
    h2(class: "household__heading") { t("households.people.invited") }
    ul(class: "household__list") { @roster.invitations.each { |invitation| invitation_row(invitation) } }
  end

  def invitation_row(invitation)
    li(class: "household__row household__row--invited") do
      render Components::Icon.new("fa-envelope", class: "household__icon")
      div(class: "household__who") do
        p(class: "household__name") { invitation.email }
        p(class: "household__facts") { invitation_facts(invitation) }
      end
      div(class: "household__actions") { invitation_actions(invitation) }
      link(invitation) if @fresh&.profile == invitation
    end
  end

  def invitation_facts(invitation)
    plain t("households.people.invited_by", name: invitation.invited_by.display_name) if invitation.invited_by
    span(class: "household__fact") do
      if invitation.valid_invitation?
        plain t("households.people.valid_until", date: l(invitation.invitation_due_at.in_time_zone.to_date, format: :long))
      else
        render Components::StatusBadge.new(tone: :warning, label: t("households.people.expired"))
      end
    end
  end

  def invitation_actions(invitation)
    if policy(invitation).renew_invitation?
      render Components::ItemAction.new(id: button_id(invitation, :renew), href: household_invitation_renewals_path(invitation), icon: "fa-link",
                                        method: :post, turbo_stream: true,
                                        label: t("households.people.renew"), confirm: t("households.people.renew_confirm", email: invitation.email))
    end
    if policy(invitation).cancel_invitation?
      render Components::ItemAction.new(id: button_id(invitation, :cancel), href: household_invitation_path(invitation), icon: "fa-trash", method: :delete,
                                        turbo_stream: true, danger: true, data: { focus_fallback: focus_fallback(invitation) },
                                        label: t("households.people.cancel"), confirm: t("households.people.cancel_confirm", email: invitation.email))
    end
  end

  # The link just made, once: selected on focus, copied with its button.
  def link(profile)
    div(class: "household__link", data: { controller: "clipboard", clipboard_copied_value: t("households.link.copied") }) do
      p(class: "household__link-hint") { link_hint(profile) }
      div(class: "household__link-row") do
        input(type: "text", readonly: true, class: "input household__link-url", value: link_url(profile),
              aria: { label: t("households.link.label") }, data: { clipboard_target: "source", action: "focus->clipboard#select" })
        render Components::ItemAction.new(icon: "fa-copy", label: t("households.link.copy"), data: { action: "clipboard#copy", clipboard_target: "button" })
      end
    end
  end
end
