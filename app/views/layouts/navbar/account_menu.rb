# frozen_string_literal: true

# The account menu, behind the avatar in the top bar's right: who's signed
# in, their Household page, "This device" (Views::Layouts::DeviceSettings), the
# language, and Log out last. A dropdown (dropdown_controller.js) that
# hangs from the top bar like the bell's.
class Views::Layouts::Navbar::AccountMenu < Views::Base
  include Phlex::Rails::Helpers::ButtonTo

  PANEL_ID = "account-menu-panel"

  # push_digests: the devices with push on, for "This device".
  def initialize(profile:, location:, push_digests:)
    @profile = profile
    @location = location
    @push_digests = push_digests
  end

  def view_template
    div(class: "account-menu", data: { controller: "dropdown" }) do
      button(
        type: "button",
        class: "account-menu__button",
        aria: { label: t("navbar.account.label"), expanded: "false", controls: PANEL_ID },
        data: { dropdown_target: "toggler", action: "click->dropdown#toggle" },
      ) do
        span(class: "account-menu__avatar", aria: { hidden: "true" }) { render Components::Icon.new("fa-user") }
      end

      div(id: PANEL_ID, class: "account-menu__panel", data: { dropdown_target: "menu" }) do
        render_who
        div(class: "account-menu__group") { render_household_link }
        div(class: "account-menu__group") { render Views::Layouts::DeviceSettings.new(profile: @profile, push_digests: @push_digests) }
        render_locale
        div(class: "account-menu__group") { render_logout }
      end
    end
  end

  private

  def render_who
    div(class: "account-menu__who") do
      span(class: "account-menu__avatar", aria: { hidden: "true" }) { render Components::Icon.new("fa-user") }
      div(class: "account-menu__meta") do
        p(class: "account-menu__name") { @profile.full_name }
        p(class: "account-menu__household") { @profile.household.name }
      end
    end
  end

  def render_household_link
    current = @location.current?(household_path)
    a(href: household_path, class: "account-menu__link#{" is-current" if current}", aria: { current: ("page" if current) }) do
      render Components::Icon.new("fa-people-roof")
      span { t("navbar.links.household") }
    end
  end

  def render_locale
    div(class: "account-menu__group account-menu__locale", role: "group", aria: { label: t("navbar.locale.label") }) do
      p(class: "account-menu__caption") { t("navbar.locale.label") }
      I18n.available_locales.each do |locale|
        current = locale == I18n.locale
        button_to(
          locale_path,
          method: :patch,
          params: { locale: locale },
          class: "account-menu__option#{" is-current" if current}",
          form_class: "account-menu__form",
          aria: { current: (current ? "true" : nil) },
        ) do
          # Each language's name is in that language, and says so, so a
          # screen reader speaking another one pronounces it right.
          span(lang: locale) { t("navbar.locale.names.#{locale}") }
          render Components::Icon.new("fa-check") if current
        end
      end
    end
  end

  # A full page load, as signing in is: nothing of this person's pages stays
  # in Turbo's cache, and the next page comes with the next session's policy.
  def render_logout
    button_to(destroy_profile_session_path, method: :delete, form: { data: { turbo: false } }, form_class: "account-menu__form",
                                            class: "account-menu__logout") do
      render Components::Icon.new("fa-arrow-right-from-bracket")
      span { t("navbar.profile.logout") }
    end
  end
end
