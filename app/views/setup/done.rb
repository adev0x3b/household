# frozen_string_literal: true

# The answer to the first setup when it invited housemates: the household
# is ready, and each invitation's link is shown this once, to copy and hand
# over (nothing is emailed). Then on to home.
class Views::Setup::Done < Views::Base
  # invitations: the Households::Invite results, each with its token.
  def initialize(household:, invitations:)
    @household = household
    @invitations = invitations
  end

  def page_title = t("setup.done.title")

  def view_template
    div(class: "report-page setup") do
      header(class: "setup__header") do
        h1(class: "setup__title") { t("setup.done.title") }
        p(class: "report-hint") { t("setup.done.hint", household: @household.name) }
      end
      render Components::Panel.new(title: t("setup.done.links"), hint: t("setup.done.links_hint")) do
        ul(class: "setup__links") { @invitations.each { |invitation| li { link(invitation) } } }
      end
      div(class: "report-footer setup__nav") do
        a(href: root_path, class: "modal__btn modal__btn--primary") do
          plain t("setup.done.home")
          whitespace
          render Components::Icon.new("fa-arrow-right")
        end
      end
    end
  end

  private

  def link(invitation)
    person = invitation.profile
    div(class: "household__link", data: { controller: "clipboard", clipboard_copied_value: t("households.link.copied") }) do
      p(class: "household__link-hint") { t("households.link.invitation", email: person.email) }
      div(class: "household__link-row") do
        input(type: "text", readonly: true, class: "input household__link-url", value: accept_profile_invitation_url(invitation_token: invitation.token),
              aria: { label: t("setup.done.link_label", name: person.first_name.presence || person.email) },
              data: { clipboard_target: "source", action: "focus->clipboard#select" })
        render Components::ItemAction.new(icon: "fa-copy", label: t("households.link.copy"), data: { action: "clipboard#copy", clipboard_target: "button" })
      end
    end
  end
end
