# frozen_string_literal: true

# Everything on the Links page that changes: requests to approve, one's own
# requests, link requests, the links themselves, housemates to link with.
# One element (#links-page), replaced after every change. What it lists is
# handed in as a Links::Page, read for this viewer alone or for everyone a
# change is pushed to at once.
class Views::Links::Sections < Views::Base
  ID = "links-page"

  def initialize(viewer:, page:)
    @viewer = viewer
    @page = page
  end

  def dom_id = ID

  def view_template
    div(id: ID, class: "links__sections") do
      group(:approvals) { approvals.each { |approval| render Views::Links::ApprovalRow.new(approval: approval, viewer: @viewer) } } if approvals.any?
      group(:asked) { requests.each { |approval| render Views::Links::ApprovalRow.new(approval: approval, viewer: @viewer) } } if requests.any?
      group(:incoming) { incoming.each { |link| link_request_row(link, link.requester) } } if incoming.any?
      group(:linked) do
        if links.any?
          links.each { |link| render Views::Links::Partner.new(link: link, viewer: @viewer) }
        else
          render Components::EmptyState.new(icon: "fa-link", message: t("links.index.no_links"))
        end
      end
      if housemates.any? || outgoing.any?
        group(:housemates) do
          outgoing.each { |link| outgoing_row(link) }
          housemates.each { |housemate| housemate_row(housemate) }
        end
      end
    end
  end

  private

  def group(key, &)
    div(class: "links__section links__section--#{key}") do
      h2(class: "household__heading") { t("links.index.sections.#{key}") }
      div(class: "household__list", &)
    end
  end

  def approvals = @approvals ||= @page.approvals(@viewer)
  def requests = @requests ||= @page.requests(@viewer)
  def incoming = @incoming ||= @page.incoming(@viewer)
  def outgoing = @outgoing ||= @page.outgoing(@viewer)
  def links = @links ||= @page.links(@viewer)
  def housemates = @housemates ||= @page.housemates(@viewer)

  def link_request_row(link, person)
    div(class: "household__row") do
      render Components::Icon.new("fa-link", class: "household__icon")
      div(class: "household__who") do
        p(class: "household__name") { person.full_name }
        p(class: "household__facts") { t("links.requests.wants", name: person.display_name) }
      end
      div(class: "household__actions") do
        render Components::ItemAction.new(href: link_acceptance_path(link), icon: "fa-check", method: :post, turbo_stream: true,
                                          label: t("links.requests.accept", name: person.display_name))
        render Components::ItemAction.new(href: link_path(link), icon: "fa-xmark", method: :delete, turbo_stream: true, danger: true,
                                          label: t("links.requests.decline", name: person.display_name))
      end
    end
  end

  def outgoing_row(link)
    person = link.addressee
    div(class: "household__row") do
      render Components::Icon.new("fa-hourglass-half", class: "household__icon")
      div(class: "household__who") do
        p(class: "household__name") { person.full_name }
        p(class: "household__facts") { t("links.requests.waiting", name: person.display_name) }
      end
      div(class: "household__actions") do
        render Components::ItemAction.new(href: link_path(link), icon: "fa-xmark", method: :delete, turbo_stream: true, danger: true,
                                          label: t("links.requests.cancel", name: person.display_name))
      end
    end
  end

  def housemate_row(person)
    div(class: "household__row") do
      render Components::Icon.new("fa-user", class: "household__icon")
      div(class: "household__who") do
        p(class: "household__name") { person.full_name }
        p(class: "household__facts") { person.username }
      end
      div(class: "household__actions") do
        render Components::ItemAction.new(href: links_path(profile_id: person.id), icon: "fa-link", method: :post, turbo_stream: true,
                                          label: t("links.requests.link", name: person.display_name))
      end
    end
  end
end
