# frozen_string_literal: true

# "This device", in the account menu (Views::Layouts::Navbar::AccountMenu):
# installing the app (install_controller.js) and this browser's push
# notifications (push_controller.js). Also where the browser's time zone is
# sent from (time_zone_controller.js), since it's on every signed-in page.
#
# Push is off where the server has no VAPID keys or the installation turned
# it off (PushNotifications.enabled?): the line says so.
class Views::Layouts::DeviceSettings < Views::Base
  PUSH_STATES = %w[on off denied unsupported install_first].freeze

  # push_digests: the digests of the endpoints that have push on, so this
  # browser can tell whether it is one of them (push_controller.js).
  def initialize(profile:, push_digests:)
    @profile = profile
    @push_digests = push_digests
  end

  def view_template
    div(class: "navbar-device", data: { controller: "time-zone", time_zone_current_value: @profile.time_zone.to_s, time_zone_url_value: time_zone_path }) do
      p(class: "navbar-device__title") { t("pwa.device.title") }
      render_install
      render_push
    end
  end

  private

  def render_install
    div(data: { controller: "install" }) do
      button(type: "button", class: "navbar-device__row navbar-device__install", hidden: true,
             data: { install_target: "button", action: "install#install" }) do
        render Components::Icon.new("fa-download")
        span(class: "navbar-device__label") { t("pwa.device.install") }
      end
      p(class: "navbar-device__hint", hidden: true, data: { install_target: "iosHint" }) do
        render Components::Icon.new("fa-arrow-up-from-bracket")
        whitespace
        plain t("pwa.device.ios_hint")
      end
    end
  end

  def render_push
    if (reason = push_unavailable)
      div(class: "navbar-device__row") do
        render Components::Icon.new("fa-bell-slash", style: :regular)
        span(class: "navbar-device__label") do
          plain t("pwa.device.notifications")
          span(class: "navbar-device__status") { t("push.unavailable.#{reason}") }
        end
      end
      return
    end

    label(class: "navbar-device__row", data: { controller: "push", **push_values }) do
      render Components::Icon.new("fa-bell", style: :regular)
      span(class: "navbar-device__label") do
        plain t("pwa.device.notifications")
        span(class: "navbar-device__status", data: { push_target: "status" })
      end
      input(type: "checkbox", role: "switch", class: "navbar-device__switch", disabled: true,
            data: { push_target: "switch", action: "change->push#toggle" })
    end
  end

  def push_unavailable = ("not_configured" unless PushNotifications.enabled?)

  def push_values
    {
      push_public_key_value: PushNotifications.public_key,
      push_url_value: push_subscription_path,
      push_digests_value: @push_digests.to_json,
      push_labels_value: PUSH_STATES.index_with { t("push.states.#{_1}") }.to_json
    }
  end
end
