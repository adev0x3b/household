# frozen_string_literal: true

# The navbar's bell: the unread count, and a dropdown whose list loads the
# first time it opens (a lazy frame, see Views::Notifications::List)
# and is read again each time it opens again (bell_controller.js). New
# notifications arrive live while it is open: see Notifications::Broadcaster.
class Views::Notifications::Bell < Views::Base
  include Phlex::Rails::Helpers::ButtonTo
  include Phlex::Rails::Helpers::TurboFrameTag

  PANEL_ID = "notifications-panel"

  # unread: how many notifications the person hasn't read.
  def initialize(unread:)
    @unread = unread
  end

  def view_template
    div(class: "notifications", data: { controller: "dropdown bell", action: "dropdown:opened->bell#refresh" }) do
      button(
        class: "notifications__bell",
        type: "button",
        aria: { expanded: "false", controls: PANEL_ID },
        data: { dropdown_target: "toggler", action: "click->dropdown#toggle" },
      ) do
        render Components::Icon.new("fa-bell")
        # Its name is these words and the count beside them, as both are seen.
        span(class: "is-sr-only") { t("notifications.title") }
        render Views::Notifications::Badge.new(count: @unread)
      end

      div(id: PANEL_ID, class: "notifications__panel", data: { dropdown_target: "menu" }) do
        div(class: "notifications__header") do
          span(class: "notifications__title") { t("notifications.title") }
          button_to(
            t("notifications.mark_all_read"),
            notification_list_read_receipt_path,
            class: "notifications__read-all",
            form_class: "notifications__read-all-form",
            form: { data: { turbo_stream: true } },
          )
        end

        # The same on every page and kept live by the :notifications stream,
        # so a page refresh (morph) leaves it alone instead of morphing it
        # back into its loading placeholder. Read again on opening, by a
        # morph that keeps where its panel was scrolled.
        turbo_frame_tag(
          Views::Notifications::List::FRAME_ID,
          src: notifications_path, loading: :lazy, target: "_top", refresh: :morph,
          data: { turbo_permanent: true, bell_target: "list" },
        ) do
          p(class: "notifications__loading") { t("notifications.loading") }
        end
      end
    end
  end
end
