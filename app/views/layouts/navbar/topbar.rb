# frozen_string_literal: true

# The fixed top bar, the page's banner: from a tablet up the burger that
# opens the navigation, then the wordmark, the page's controls, the bell and
# the account menu. The page's name is the page's own (Components::PageHeader),
# never repeated here.
class Views::Layouts::Navbar::Topbar < Views::Base
  # unread_notifications: the bell's count; push_digests: the devices with
  # push on, for "This device" in the account menu.
  def initialize(profile:, location:, unread_notifications:, push_digests:, page_controls: nil)
    @profile = profile
    @location = location
    @unread_notifications = unread_notifications
    @push_digests = push_digests
    @page_controls = page_controls
  end

  def view_template
    header(class: "navbar-topbar", data: { navbar_target: "behind" }) do
      div(class: "navbar-topbar-left") do
        # On a phone the bottom bar's Menu tab opens the navigation instead; the stylesheet hides this one
        button(
          class: "navbar-burger",
          type: "button",
          aria: { label: t("navbar.menu"), expanded: "false", controls: Views::Layouts::Navbar::SHEET_ID },
          data: { navbar_target: "toggler", action: "navbar#toggle" },
        ) { render Components::Icon.new("fa-bars") }
        a(href: root_path, class: "navbar-logo-link") do
          span(class: "navbar-logo-text") { t("app.name") }
        end
      end

      # In the order they are seen, left to right, which is also the order Tab takes
      if @page_controls
        div(class: "navbar-topbar-controls") { render @page_controls }
      end

      div(class: "navbar-topbar-right") do
        render Views::Notifications::Bell.new(unread: @unread_notifications)
        render Views::Layouts::Navbar::AccountMenu.new(profile: @profile, location: @location, push_digests: @push_digests)
      end
    end
  end
end
