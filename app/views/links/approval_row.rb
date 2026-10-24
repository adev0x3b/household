# frozen_string_literal: true

# A change a linked housemate asked for on someone's item, as its owner
# sees it (approve / decline) or as its asker does (take it back, or how it
# went): who, what, which item, day and dose, and what would change.
class Views::Links::ApprovalRow < Views::Base
  LOOKS = {
    "pending" => Components::StatusLook.new(tone: :neutral, icon: "fa-hourglass-half"),
    "approved" => Components::StatusLook.new(tone: :good, icon: "fa-check"),
    "declined" => Components::StatusLook.new(tone: :neutral, icon: "fa-xmark"),
    "failed" => Components::StatusLook.new(tone: :critical, icon: "fa-triangle-exclamation"),
    "withdrawn" => Components::StatusLook.new(tone: :neutral, icon: "fa-rotate-left"),
    "cancelled" => Components::StatusLook.new(tone: :neutral, icon: "fa-ban")
  }.freeze

  def initialize(approval:, viewer:)
    @approval = approval
    @viewer = viewer
    @mine = approval.owner_id == viewer.id
  end

  def view_template
    div(id: "link-approval-#{@approval.id}", class: "household__row links__approval") do
      render Components::Icon.new(LOOKS.fetch(@approval.status).icon, class: "household__icon")
      div(class: "household__who") do
        p(class: "household__name") { headline }
        p(class: "household__facts") do
          span { @approval.title }
          span { [ l(@approval.date, format: :long), @approval.when_label ].compact.join(" ") } if @approval.date
          status_badge unless @approval.pending?
          render Components::StatusBadge.new(tone: :warning, label: t("links.approvals.changed_since")) if @mine && @approval.pending? && @approval.changed_since?
        end
        changes if @approval.preview.any?
        p(class: "household__facts") { t("links.approvals.failures.#{@approval.failure}") } if @approval.failed? && @approval.failure
      end
      div(class: "household__actions") { actions }
    end
  end

  private

  def status_badge
    status = @approval.status
    render LOOKS.fetch(status).badge(label: t("links.approvals.status.#{status}"))
  end

  def headline
    key = @mine ? "asks" : "asked"
    person = @mine ? @approval.requester : @approval.owner
    t("links.approvals.#{key}.#{@approval.verb}", name: person.display_name, thing: t("links.things.#{@approval.event_type.underscore}"))
  end

  def changes
    ul(class: "links__changes") do
      @approval.preview.each do |row|
        change = ::Links::Approvals::Change.new(row, kind: @approval.kind)
        li do
          span(class: "links__change-field") { change.field }
          plain " "
          if change.from
            del { change.from }
            plain " → "
          end
          ins { change.to || t("links.approvals.cleared") }
        end
      end
    end
  end

  def actions
    return unless @approval.live?

    if @mine
      render Components::ItemAction.new(href: link_approval_consent_path(@approval), icon: "fa-check", method: :post, turbo_stream: true,
                                        label: t("links.approvals.approve"))
      render Components::ItemAction.new(href: link_approval_path(@approval), icon: "fa-xmark", method: :delete, turbo_stream: true, danger: true,
                                        label: t("links.approvals.decline"))
    else
      render Components::ItemAction.new(href: link_approval_path(@approval), icon: "fa-rotate-left", method: :delete, turbo_stream: true,
                                        label: t("links.approvals.withdraw"), confirm: t("links.approvals.withdraw_confirm"))
    end
  end
end
