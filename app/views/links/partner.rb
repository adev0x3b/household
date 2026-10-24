# frozen_string_literal: true

# One link, from one side: who, since when, and the way to end it; then
# what the viewer lets them do with the viewer's items, and, folded, what
# they let the viewer do with theirs. Each kind of item has a row of pills
# for seeing it (off, on) and for editing, adding and deleting it (off,
# ask, on), and a pill saves on tap (LinkGrantsController).
class Views::Links::Partner < Views::Base
  LEVEL_ICONS = { "off" => "fa-ban", "ask" => "fa-hand", "on" => "fa-check" }.freeze

  def initialize(link:, viewer:)
    @link = link
    @viewer = viewer
    @partner = link.partner_of(viewer)
  end

  def view_template
    div(id: "link-#{@link.id}", class: "links__partner") do
      heading_row
      h3(class: "links__subheading") { t("links.partner.they_can", name: @partner.display_name) }
      div(class: "links__grants") { @link.grants_from(@viewer).each { |grant| editable(grant) } }
      details(class: "links__theirs") do
        summary(class: "links__theirs-summary") do
          render Components::Icon.new("fa-chevron-right", class: "links__theirs-chevron")
          span(class: "links__subheading") { t("links.partner.you_can", name: @partner.display_name) }
        end
        ul(class: "links__summary") { @link.grants_from(@partner).each { |grant| summary_row(grant) } }
      end
    end
  end

  private

  def heading_row
    div(class: "household__row links__partner-header") do
      render Components::Icon.new("fa-link", class: "household__icon")
      div(class: "household__who") do
        p(class: "household__name") { @partner.full_name }
        p(class: "household__facts") { t("links.partner.since", date: l((@link.accepted_at || @link.created_at).in_time_zone.to_date, format: :long)) }
      end
      div(class: "household__actions") do
        render Components::ItemAction.new(href: link_path(@link), icon: "fa-link-slash", method: :delete, turbo_stream: true, danger: true,
                                          label: t("links.partner.unlink", name: @partner.display_name),
                                          confirm: t("links.partner.unlink_confirm", name: @partner.display_name))
      end
    end
  end

  # A kind of event (Event.types), with its icon and the colour of the
  # section a new one starts in.
  def type_label(grant)
    type = grant.kind
    div(class: "links__type section--#{type.starting_section}") do
      render Components::Icon.new(Views::Calendar::Cards.for(type).icon, class: "links__type-icon")
      span { type_name(grant) }
    end
  end

  def type_name(grant) = t("links.types.#{grant.event_type.underscore}")

  def editable(grant)
    div(class: "links__grant") do
      type_label(grant)
      div(class: "links__permissions") do
        LinkGrant::ACTIONS.each do |action|
          next if action != "read" && grant.read_off?

          div(class: "links__permission") do
            span(class: "links__permission-label") { t("links.partner.actions.#{action}") }
            render Components::SegmentedFilter.new(
              label: t("links.partner.actions_label", action: t("links.partner.actions.#{action}"), type: type_name(grant)),
              current: grant.level(action), method: :patch,
              items: LinkGrant.levels_for(action).map { |level| pill(grant, action, level) }
            )
          end
        end
        p(class: "links__hidden") { t("links.partner.hidden", name: @partner.display_name) } if grant.read_off?
      end
    end
  end

  def pill(grant, action, level)
    Components::NavItem.new(key: level, label: t("links.levels.#{level}"), icon: LEVEL_ICONS.fetch(level),
                            href: link_grant_path(@link, grant.event_type, permission: action, level: level))
  end

  # A kind of item and what the partner lets one do with it beyond seeing it
  # ("Edit: ask me · Add: ask me · Delete: no"), or that it is hidden.
  def summary_row(grant)
    li(class: "links__summary-row") do
      type_label(grant)
      span(class: "links__summary-levels") do
        if grant.read_off?
          plain t("links.partner.hidden_from_you")
        else
          plain LinkGrant::ACTIONS.drop(1).map { |action| "#{t("links.partner.actions.#{action}")}: #{t("links.levels.#{grant.level(action)}").downcase}" }.join(" · ")
        end
      end
    end
  end
end
